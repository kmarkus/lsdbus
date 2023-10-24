/*
 * sd_event based event loop
 */

#include "lsdbus.h"
#include "string.h"

#define REG_EVSRC_TABLE		"lsdbus.evsrc_table"

static int evsrc_tostring(lua_State *L)
{
	int ret;
	const char *desc;
	sd_event_source *evsrc = *((sd_event_source**) luaL_checkudata(L, -1, EVSRC_MT));
	ret = sd_event_source_get_description(evsrc, &desc);
	lua_pushfstring(L, "event_source [%s] %p", (ret<0)?"unkown":desc, evsrc);
	return 1;
}

static int evsrc_set_enabled(lua_State *L)
{
	int ret, enabled;

	sd_event_source *evsrc = *((sd_event_source**) luaL_checkudata(L, -2, EVSRC_MT));
	enabled = luaL_checkinteger(L, -1);

	ret = sd_event_source_set_enabled(evsrc, enabled);

	if (ret<0)
		luaL_error(L, "event_source_set_enabled failed: %s", strerror(-ret));

	return 0;
}

/* just set it to floating */
static int evsrc_gc(lua_State *L)
{
	sd_event_source *evsrc = *((sd_event_source**) luaL_checkudata(L, 1, EVSRC_MT));
	sd_event_source_set_floating(evsrc, 1);
	printf("set evsrc %p to floating\n", evsrc);
	return 0;
}

static int evsrc_unref(lua_State *L)
{
	int ret;
	sd_event_source *evsrc = *((sd_event_source**) luaL_checkudata(L, 1, EVSRC_MT));

	/* signal evsrc ? */
	ret = sd_event_source_get_signal(evsrc);
	if (ret>0) {
		sigset_t ss;
		sigemptyset(&ss);
		sigaddset(&ss, ret);
		sigprocmask(SIG_UNBLOCK, &ss, NULL);
	}

	sd_event_source_unref(evsrc);

	lua_newtable(L);
	lua_setmetatable(L, -2);
	return 0;
}

const luaL_Reg lsdbus_evsrc_m [] = {
	{ "set_enabled", evsrc_set_enabled },
	{ "unref", evsrc_unref },
	{ "__tostring", evsrc_tostring },
	{ "__gc", evsrc_gc },
	{ NULL, NULL }
};


/**
 * evl_get: return event loop (and create if it doesn't exist)
 */
sd_event* evl_get(lua_State *L, sd_bus *bus)
{
	int ret;
	sd_event *loop;

	loop = sd_bus_get_event(bus);

	if (loop)
		goto out;

	ret = sd_event_new(&loop);

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

int evl_loop(lua_State *L)
{
	int ret;
	sd_bus *b = lua_checksdbus(L, 1);
	sd_event *loop = evl_get(L, b);

	ret = sd_event_loop(loop);

	if(ret<0)
		luaL_error(L, "sd_event_loop exited with error %s", strerror(-ret));

	return 0;
}

int evl_run(lua_State *L)
{
	int ret;
	uint64_t usec;

	sd_bus *b = lua_checksdbus(L, 1);
	sd_event *loop = evl_get(L, b);

	usec = luaL_optinteger(L, 2, 0);

	ret = sd_event_run(loop, usec);

	if(ret<0)
		luaL_error(L, "sd_event_run exited with error %s", strerror(-ret));

	lua_pushinteger(L, ret);

	return 1;
}

/* call sd_event_exit */
int evl_exit(lua_State *L)
{
	int ret, code;
	sd_bus *b;
	sd_event *loop;

	b = lua_checksdbus(L, 1);
	code = luaL_optinteger(L, 2, 0);
	loop = sd_bus_get_event(b);

	if (loop == NULL)
		luaL_error(L, "failed to exit loop: bus not attached");

	ret = sd_event_exit(loop, code);

	if (ret<0)
		luaL_error(L, "sd_event_exit failed: %s", strerror(-ret));

	return 0;
}

static int evl_sig_callback(sd_event_source *s, const struct signalfd_siginfo *si, void *userdata)
{
	(void) si;
	int sig, top;
	sig = sd_event_source_get_signal(s);
	lua_State *L = (lua_State*) userdata;
	top  = lua_gettop(L);

	dbg("received signal %d", sd_event_source_get_signal(s));

	regtab_get(L, REG_EVSRC_TABLE, s);
	lua_pushvalue(L, 1);		/* bus */
	lua_pushinteger(L, sig);	/* signal */

	lua_call(L, 2, 0);
	lua_settop(L, top);
	return 0;
}


int evl_add_signal(lua_State *L)
{
	int ret, sig;
	sigset_t ss;
	sd_event_source *source, **sourcep;

	sd_bus *b = lua_checksdbus(L, 1);
	sig = luaL_checkinteger(L, 2);
	luaL_checktype(L, 3, LUA_TFUNCTION);

	sd_event *loop = evl_get(L, b);

	dbg("adding signal %d", sig);

	if (sigemptyset(&ss) < 0 || sigaddset(&ss, sig))
		luaL_error(L, "sigemptyset failed: %m");

	if (sigprocmask(SIG_BLOCK, &ss, NULL) < 0)
		luaL_error(L, "sigprocmask failed: %m");

	ret = sd_event_add_signal(loop, &source, sig, evl_sig_callback, L);

	if (ret<0)
		luaL_error(L, "adding signal failed: %s", strerror(-ret));

	regtab_store(L,	REG_EVSRC_TABLE, source, 3);

	sourcep = (sd_event_source**) lua_newuserdata(L, sizeof(sd_event_source*));
	*sourcep = source;

	luaL_getmetatable(L, EVSRC_MT);
	lua_setmetatable(L, -2);
	sd_event_source_set_description(source, "unix_signal");

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
	lua_pushvalue(L, 1);		/* bus */
	lua_pushinteger(L, usec);	/* usec */
	lua_call(L, 2, 0);

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
	uint64_t now, usec, accuracy;
	sd_event_source *evsrc, **evsrcp;

	sd_bus *b = lua_checksdbus(L, 1);
	usec = luaL_checkinteger(L, 2);
	accuracy = luaL_optinteger(L, 3, 0);
	luaL_checktype(L, 4, LUA_TFUNCTION);

	sd_event *loop = evl_get(L, b);

	if(!loop)
		luaL_error(L, "bus has no loop");

	ret = sd_event_now(loop, CLOCK_MONOTONIC, &now);

	if(ret<0)
		luaL_error(L, "failed get current time: %s", strerror(-ret));

	ret = sd_event_add_time(
		loop, &evsrc, CLOCK_MONOTONIC, now+usec, accuracy, timer_callback, L);

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
	sd_event_source_set_description(evsrc, "periodic");

	luaL_getmetatable(L, EVSRC_MT);
	lua_setmetatable(L, -2);

	return 1;
}

/* io */
static int evl_io_callback(sd_event_source *s, int fd, uint32_t revents, void *userdata)
{
	int top;
	lua_State *L = (lua_State*) userdata;

	top  = lua_gettop(L);
	dbg("received io event %i on fd %i", revents, fd);
	regtab_get(L, REG_EVSRC_TABLE, s);

	lua_pushvalue(L, 1);	/* bus */
	lua_pushinteger(L, fd);
	lua_pushinteger(L, revents);

	lua_call(L, 3, 0);
	lua_settop(L, top);
	return 0;
}

int evl_add_io(lua_State *L)
{
	int fd, ret;
	uint32_t events;
	sd_event_source *source, **sourcep;

	sd_bus *b = lua_checksdbus(L, 1);
	fd = luaL_checkinteger(L, 2);
	events = luaL_checkinteger(L, 3);
	luaL_checktype(L, 4, LUA_TFUNCTION);

	sd_event *loop = evl_get(L, b);

	ret = sd_event_add_io(loop, &source, fd, events, evl_io_callback, L);

	if (ret<0)
		luaL_error(L, "adding io event src failed: %s", strerror(-ret));

	regtab_store(L,	REG_EVSRC_TABLE, source, 4);

	sourcep = (sd_event_source**) lua_newuserdata(L, sizeof(sd_event_source*));
	*sourcep = source;

	luaL_getmetatable(L, EVSRC_MT);
	lua_setmetatable(L, -2);
	sd_event_source_set_description(source, "io");

	return 1;
}

static int evl_child_callback(sd_event_source *s, const siginfo_t *si, void *userdata)
{
	int top;
	lua_State *L = (lua_State*) userdata;

	top  = lua_gettop(L);
	dbg("received wait child (pid %i) event", si->si_pid);

	regtab_get(L, REG_EVSRC_TABLE, s);
	lua_pushvalue(L, 1);		/* bus */

	lua_newtable(L);		/* si */

	lua_pushinteger(L, si->si_pid);
	lua_setfield(L, -2, "pid");

	lua_pushinteger(L, si->si_uid);
	lua_setfield(L, -2, "uid");

	lua_pushinteger(L, si->si_status);
	lua_setfield(L, -2, "status");

	lua_pushinteger(L, si->si_code);
	lua_setfield(L, -2, "code");

	lua_call(L, 2, 0);
	lua_settop(L, top);
	return 0;
}

int evl_add_child(lua_State *L)
{
	int options, ret;
	pid_t pid;
	sigset_t ss;
	sd_event_source *source, **sourcep;
	sd_bus *bus = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));

	pid = luaL_checkinteger(L, 2);
	options = luaL_checkinteger(L, 3);
	luaL_checktype(L, 4, LUA_TFUNCTION);

	sd_event *loop = evl_get(L, bus);

	if (sigemptyset(&ss) < 0 || sigaddset(&ss, SIGCHLD))
		luaL_error(L, "sigemptyset/sigaddset failed: %m");

	if (sigprocmask(SIG_BLOCK, &ss, NULL) < 0)
		luaL_error(L, "sigprocmask failed: %m");

	dbg("add callback for pid %i (%i)", pid, options);

	ret = sd_event_add_child(loop, &source, pid, options, evl_child_callback, L);

	if (ret<0)
		luaL_error(L, "adding child pid event src failed: %s", strerror(-ret));

	regtab_store(L,	REG_EVSRC_TABLE, source, 4);

	sourcep = (sd_event_source**) lua_newuserdata(L, sizeof(sd_event_source*));
	*sourcep = source;

	sd_event_source_set_enabled(source, SD_EVENT_ON);

	luaL_getmetatable(L, EVSRC_MT);
	lua_setmetatable(L, -2);
	sd_event_source_set_description(source, "child_pid");

	return 1;
}
