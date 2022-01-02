/*
 * sd_event based event loop
 */

#include "lsdbus.h"
#include "string.h"

#define REG_EVSRC_TABLE		"lsdbus.evsrc_table"

static int evl_evsrc_tostring(lua_State *L)
{
	int ret;
	const char *desc;
	sd_event_source *evsrc = *((sd_event_source**) luaL_checkudata(L, -1, EVSRC_MT));
	ret = sd_event_source_get_description(evsrc, &desc);
	lua_pushfstring(L, "event_source: %s (%p)", (ret<0)?"":desc, evsrc);
	return 1;
}

static int evl_evsrc_set_enabled(lua_State *L)
{
	int ret, enabled;

	sd_event_source *evsrc = *((sd_event_source**) luaL_checkudata(L, -2, EVSRC_MT));
	enabled = luaL_checkinteger(L, -1);

	ret = sd_event_source_set_enabled(evsrc, enabled);

	if (ret<0)
		luaL_error(L, "event_source_set_enabled failed: %s", strerror(-ret));

	return 0;
}


/**
 * evl_get: return event loop (and create if it doesn't exist)
 */
static sd_event* evl_get(lua_State *L, sd_bus *bus)
{
	int ret;
	sd_event *loop;

	loop = sd_bus_get_event(bus);

	if (loop)
		goto out;

	ret = sd_event_default(&loop);

	if (ret<0)
		luaL_error(L, "failed to create sd_event_loop: %s", strerror(-ret));

	ret = sd_bus_attach_event(bus, loop, SD_EVENT_PRIORITY_NORMAL);

	if (ret<0)
		luaL_error(L, "failed to attach bus to event loop: %s", strerror(-ret));
out:
	return loop;
}

void evl_cleanup(sd_bus *bus)
{
	sd_event *loop = sd_bus_get_event(bus);

	if (loop)
		sd_event_unref(loop);
}

void evl_loop(lua_State *L, sd_bus *bus)
{
	int ret;
	sd_event *loop = evl_get(L, bus);

	ret = sd_event_loop(loop);

	if(ret<0)
		luaL_error(L, "sd_event_loop exited with error %s", strerror(-ret));
}

/* call sd_event_exit */
int evl_exit(lua_State *L)
{
	int ret, code;
	sd_bus *bus;
	sd_event *loop;

	bus = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	code = luaL_optinteger(L, 2, 0);
	loop = sd_bus_get_event(bus);

	if (loop == NULL)
		luaL_error(L, "failed to exit loop: bus not attached");

	ret = sd_event_exit(loop, code);

	if (ret<0)
		luaL_error(L, "sd_event_exit failed: %s", strerror(-ret));

	return 0;
}

struct ev2num { const char *name; int sig; };

static struct ev2num sigs[] = {
	{ .name="SIGTERM", .sig=SIGTERM },
	{ .name="SIGINT",  .sig=SIGINT },
	{ .name="SIGUSR1", .sig=SIGUSR1 },
	{ .name="SIGUSR2", .sig=SIGUSR2 },
};

static int evl_sig_handler(sd_event_source *s, const struct signalfd_siginfo *si, void *userdata)
{
	(void) si;
	int sig, top;
	sig = sd_event_source_get_signal(s);
	lua_State *L = (lua_State*) userdata;
	top  = lua_gettop(L);

	dbg("received signal %d", sd_event_source_get_signal(s));

	regtab_get(L, REG_EVSRC_TABLE, s);

	for(unsigned int i=0; i<ARRAY_SIZE(sigs); i++) {
		if (sigs[i].sig == sig)
			lua_pushstring(L, sigs[i].name);
	}

	lua_call(L, 1, 0);
	lua_settop(L, top);
	return 0;
}


int evl_add_signal(lua_State *L)
{
	int ret, sig = -1;
	sigset_t ss;
	sd_event_source *source, **sourcep;

	sd_bus *bus = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	const char *signame = luaL_checkstring(L, 2);
	luaL_checktype(L, 3, LUA_TFUNCTION);

	sd_event *loop = evl_get(L, bus);

	for(unsigned int i=0; i<ARRAY_SIZE(sigs); i++) {
		if(strcmp(signame, sigs[i].name) == 0) {
			sig = sigs[i].sig;
			break;
		}
	}

	if (sig == -1)
		luaL_error(L, "unsupported signal %s", signame);

	dbg("adding signal %s (%d)", signame, sig);

	if (sigemptyset(&ss) < 0 || sigaddset(&ss, sig))
		luaL_error(L, "sigemptyset failed: %m");

	if (sigprocmask(SIG_BLOCK, &ss, NULL) < 0)
		luaL_error(L, "sigprocmask failed: %m");

	ret = sd_event_add_signal(loop, &source, sig, evl_sig_handler, L);

	if (ret<0)
		luaL_error(L, "adding signal failed: %s", strerror(-ret));

	regtab_store(L,	REG_EVSRC_TABLE, source, 3);

	sourcep = (sd_event_source**) lua_newuserdata(L, sizeof(sd_event_source*));
	*sourcep = source;

	luaL_getmetatable(L, EVSRC_MT);
	lua_setmetatable(L, -2);

	return 1;
}

static int timer_callback(sd_event_source *evsrc, uint64_t usec, void* userdata)
{
	int ret, top;
	uint64_t period, now;
	sd_event *loop;

	lua_State *L = (lua_State*) userdata;

	top = lua_gettop(L);

	regtab_get(L, REG_EVSRC_TABLE, evsrc);

	lua_rawgeti(L, -1, 2);
	period = lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_rawgeti(L, -1, 1);
	lua_call(L, 0, 0);

	/* rearm */
	loop = sd_event_source_get_event(evsrc);

	ret = sd_event_now(loop, CLOCK_MONOTONIC, &now);

	if (ret<0)
		luaL_error(L, "timer_callback: failed to retrieve now: %s", strerror(-ret));

	/* compute next trigger time, since the event source may have
	 * been disabled */
	while(usec <= now)
		usec += period;
	
	sd_event_source_set_time(evsrc, usec);
	sd_event_source_set_enabled(evsrc, SD_EVENT_ON);

	lua_settop(L, top);
	return 0;
}

int evl_add_periodic(lua_State *L)
{
	int ret;
	uint64_t usec, accuracy;
	sd_event_source *evsrc, **evsrcp;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	usec = luaL_checkinteger(L, 2);
	accuracy = luaL_optinteger(L, 3, 0);
	luaL_checktype(L, 4, LUA_TFUNCTION);

	sd_event *loop = evl_get(L, b);

	if(!loop)
		luaL_error(L, "bus has no loop");

	ret = sd_event_add_time_relative(
		loop, &evsrc, CLOCK_MONOTONIC, usec, accuracy, timer_callback, L);

	if(ret<0)
		luaL_error(L, "failed add relativ time source: %s",
			   strerror(-ret));

	lua_newtable(L);
	lua_pushvalue(L, 4);
	lua_rawseti(L, 5, 1);
	lua_pushinteger(L, usec);
	lua_rawseti(L, 5, 2);

	regtab_store(L,	REG_EVSRC_TABLE, evsrc, -1);

	evsrcp = (sd_event_source**) lua_newuserdata(L, sizeof(sd_event_source*));
	*evsrcp = evsrc;

	luaL_getmetatable(L, EVSRC_MT);
	lua_setmetatable(L, -2);

	return 1;
}

const luaL_Reg lsdbus_evsrc_m [] = {
	{ "set_enabled", evl_evsrc_set_enabled },
	{ "__tostring", evl_evsrc_tostring },
	{ NULL, NULL }
};