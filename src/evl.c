/*
 * sd_event based event loop
 */

#include "lsdbus.h"
#include "string.h"

#define REG_EVSRC_TABLE		"lsdbus.evsrc_table"

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
	int sig = sd_event_source_get_signal(s);
	lua_State *L = (lua_State*) userdata;

	dbg("received signal %d", sd_event_source_get_signal(s));

	regtab_get(L, REG_EVSRC_TABLE, s);

	for(unsigned int i=0; i<ARRAY_SIZE(sigs); i++) {
		if (sigs[i].sig == sig)
			lua_pushstring(L, sigs[i].name);
	}

	lua_call(L, 1, 0);
	return 0;
}


int evl_add_signal(lua_State *L)
{
	int ret, sig = -1;
	sigset_t ss;
	sd_event_source *source;

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

	return 0;
}
