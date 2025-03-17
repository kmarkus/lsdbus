#include <signal.h>
#include "lsdbus.h"

static const char *const open_opts_lst [] = {
	"new",
	"system",
	"user",
	"default",
	"default_system",
	"default_user",
	NULL
};

static int(*open_funcs[])(sd_bus **bus) = {
	sd_bus_open,
	sd_bus_open_system,
	sd_bus_open_user,
	sd_bus_default,
	sd_bus_default_system,
	sd_bus_default_user,
};

#if LIBSYSTEMD_VERSION < 246
int sd_bus_interface_name_is_valid(const char *p) { (void) p; return 1; }
int sd_bus_service_name_is_valid(const char *p) { (void) p; return 1; }
int sd_bus_member_name_is_valid(const char* p)  { (void) p; return 1; }
int sd_bus_object_path_is_valid(const char* p)  { (void) p; return 1; }
#endif

/**
 * store a value in registry.regtab[k] = val [+1, +0, e]
 *
 * if the regtab doesn't exist, create it.
 */
void regtab_store(lua_State *L, const char* regtab, void *k, int validx)
{
	int _validx = lua_absindex(L, validx);

	if (lua_getfield(L, LUA_REGISTRYINDEX, regtab) != LUA_TTABLE) {
		lua_pop(L, 1);
		lua_newtable(L);
		lua_setfield(L, LUA_REGISTRYINDEX, regtab);
		lua_getfield(L, LUA_REGISTRYINDEX, regtab);
	}

	lua_pushvalue(L, _validx);
	lua_rawsetp(L, -2, k);
	lua_pop(L, 1);
}

/**
 * push the value regtab[k] onto the top of the stack [+0, +1, e]
 *
 * @return returns the type of the value
 */
int regtab_get(lua_State *L, const char* regtab, void *k)
{
	int ret;
	if (lua_getfield(L, LUA_REGISTRYINDEX, regtab) != LUA_TTABLE)
		luaL_error(L, "missing registry table %s", regtab);

	ret = lua_rawgetp(L, -1, k);
	lua_remove(L, -2);
	return ret;
}

/**
 * regtab[k]=nil
 */
void regtab_clear(lua_State *L, const char* regtab, void *k)
{
	if (lua_getfield(L, LUA_REGISTRYINDEX, regtab) == LUA_TTABLE) {
		lua_pushnil(L);
		lua_rawsetp(L, -2, k);
	}
}

const char* luaL_checkintf(lua_State *L, int arg)
{
	const char* intf = luaL_checkstring (L, arg);

	if (sd_bus_interface_name_is_valid(intf) <= 0)
		luaL_error(L, "invalid interface %s", intf);

	return intf;
}

const char* luaL_checkpath(lua_State *L, int arg)
{
	const char* path = luaL_checkstring (L, arg);

	if (sd_bus_object_path_is_valid(path) <= 0)
		luaL_error(L, "invalid object path %s", path);

	return path;
}

const char* luaL_checkmember(lua_State *L, int arg)
{
	const char* member = luaL_checkstring (L, arg);

	if (sd_bus_member_name_is_valid(member) <= 0)
		luaL_error(L, "invalid member name %s", member);

	return member;
}

const char* luaL_checkservice(lua_State *L, int arg)
{
	const char* service = luaL_checkstring (L, arg);

	if (sd_bus_service_name_is_valid(service) <= 0)
		luaL_error(L, "invalid service name %s", service);

	return service;
}

/* convenience helper from boxed lsdbus_bus to sd_bus */
sd_bus* lua_checksdbus(lua_State *L, int index)
{
	struct lsdbus_bus *lsdbus =
		(struct lsdbus_bus*) luaL_checkudata(L, index, BUS_MT);
	return lsdbus->b;
}

/* toplevel functions */
static int lsdbus_open(lua_State *L)
{
	int ret, busidx;
	struct lsdbus_bus *lsdbus;

	busidx = luaL_checkoption(L, 1, "new", open_opts_lst);

	dbg("opening %s bus connection", open_opts_lst[busidx]);

	lsdbus = (struct lsdbus_bus*) lua_newuserdata(L, sizeof(struct lsdbus_bus));

	ret = open_funcs[busidx](&lsdbus->b);

	if (ret<0)
		luaL_error(L, "%s: failed to connect to %s bus: %s",
			   __func__, open_opts_lst[busidx], strerror(-ret));

	if (open_funcs[busidx] == sd_bus_default ||
	    open_funcs[busidx] == sd_bus_default_system ||
	    open_funcs[busidx] == sd_bus_default_user) {
		lsdbus->flags =	LSDBUS_BUS_IS_DEFAULT;
	}

	luaL_getmetatable(L, BUS_MT);
	lua_setmetatable(L, -2);
	return 1;
}

/* bus methods */
static int __lsdbus_bus_call(lua_State *L, int raw)
{
	int ret;
	uint64_t timeout;
	const char *dest, *path, *intf, *memb, *types;

	sd_bus_error error = SD_BUS_ERROR_NULL;
	sd_bus_message *m = NULL;
	sd_bus_message *reply = NULL;

	sd_bus *b = lua_checksdbus(L, 1);

	dest = luaL_checkservice(L, 2);
	path = luaL_checkpath(L, 3);
	intf = luaL_checkintf(L, 4);
	memb = luaL_checkmember(L, 5);
	types = luaL_optstring(L, 6, NULL);

	ret = sd_bus_message_new_method_call(b, &m, dest, path, intf, memb);

	if (ret < 0)
		luaL_error(L, "%s: failed to create call message: %s",
			   __func__, strerror(-ret));

	if (types != NULL) {
		ret = msg_fromlua(L, m, types, 7);

		if (ret<0)
			goto out;
	}

	ret = sd_bus_get_method_call_timeout(b, &timeout);

	if(ret<0)
		luaL_error(L, "%s: failed to get call timeout: %s",
			   __func__, strerror(-ret));

	ret = sd_bus_call(b, m, 0, &error, &reply);

	if (ret<0) {
		lua_pushboolean(L, 0);
		if(sd_bus_error_is_set(&error)) {
			push_sd_bus_error(L, &error);
			ret = 2;
		} else {
			luaL_error(L, "call failed: %s", strerror(-ret));
		}

		goto out;
	}

	lua_pushboolean(L, 1);
	ret = msg_tolua(L, reply, raw);

	if (ret >= 0)
		ret++;
out:
	sd_bus_error_free(&error);
	sd_bus_message_unref(reply);
	sd_bus_message_unref(m);

	if (ret<0)
		lua_error(L);

	return ret;
}

static int lsdbus_bus_call(lua_State *L) { return __lsdbus_bus_call(L, 0); }
static int lsdbus_bus_callr(lua_State *L) { return __lsdbus_bus_call(L, 1); }

void push_string_or_nil(lua_State *L, const char* s)
{
	if (s)
		lua_pushstring(L, s);
	else
		lua_pushnil(L);
}

/**
 * generic signal callback
 */
static int signal_callback(sd_bus_message *m, void *userdata, sd_bus_error *ret_error)
{
	(void)ret_error;
	int ret, nargs, top;
	lua_State *L = (lua_State*) userdata;
	sd_bus *b = sd_bus_message_get_bus(m);
	sd_bus_slot *slot = sd_bus_get_current_slot(b);

	top = lua_gettop(L);

	regtab_get(L, REG_SLOT_TABLE, slot);

	lua_pushvalue(L, 1); /* bus */
	push_string_or_nil(L, sd_bus_message_get_sender(m));
	push_string_or_nil(L, sd_bus_message_get_path(m));
	push_string_or_nil(L, sd_bus_message_get_interface(m));
	push_string_or_nil(L, sd_bus_message_get_member(m));

	nargs = msg_tolua(L, m, 0);

	if(nargs<0)
		lua_error(L);

	ret = lua_pcall(L, 5+nargs, 1, 0);

	if (ret != LUA_OK) {
		const char *err = lua_tolstring(L, -1, NULL);
		fprintf(stderr, "error in signal callback: %s\n", err?err:"-");
		ret = -1;
	} else {
		ret = lua_tointeger(L, -1);
	}

	lua_settop(L, top);
	return ret;
}

static int lsdbus_match_signal(lua_State *L)
{
	int ret;
	sd_bus_slot *slot;
	const char *sender=NULL, *path=NULL, *intf=NULL, *memb=NULL;

	sd_bus *b = lua_checksdbus(L, 1);

	if (!lua_isnil(L, 2)) sender = luaL_checkservice(L, 2);
	if (!lua_isnil(L, 3)) path = luaL_checkpath(L, 3);
	if (!lua_isnil(L, 4)) intf = luaL_checkintf(L, 4);
	if (!lua_isnil(L, 5)) memb = luaL_checkmember(L, 5);
	luaL_checktype(L, 6, LUA_TFUNCTION);

	ret = sd_bus_match_signal(b, &slot, sender, path, intf, memb, signal_callback, L);

	if (ret<0)
		luaL_error(L, "failed to install signal match rule: %s", strerror(-ret));

	regtab_store(L,	REG_SLOT_TABLE, slot, 6);
	return lsdbus_slot_push(L, slot, LSDBUS_SLOT_TYPE_MATCH);
}

static int lsdbus_match(lua_State *L)
{
	int ret;
	sd_bus_slot *slot;
	const char *match=NULL;

	sd_bus *b = lua_checksdbus(L, 1);

	if (!lua_isnil(L, 2)) match = luaL_checkstring(L, 2);
	luaL_checktype(L, 3, LUA_TFUNCTION);

	ret = sd_bus_add_match(b, &slot, match, signal_callback, L);

	if (ret<0)
		luaL_error(L, "failed to install match rule: %s", strerror(-ret));

	/* store the callback in the registry reg.slottab[slot]=callback */
	if (lua_getfield(L, LUA_REGISTRYINDEX, REG_SLOT_TABLE) != LUA_TTABLE) {
		lua_pop(L, 1);
		lua_newtable(L);
		lua_setfield(L, LUA_REGISTRYINDEX, REG_SLOT_TABLE);
		lua_getfield(L, LUA_REGISTRYINDEX, REG_SLOT_TABLE);
	}

	lua_pushvalue(L, 3);
	lua_rawsetp(L, -2, slot);
	return lsdbus_slot_push(L, slot, LSDBUS_SLOT_TYPE_MATCH);
}

/**
 * async mesage callback
 */
static int method_callback(sd_bus_message *m, void *userdata, sd_bus_error *ret_error)
{
	(void)ret_error;
	int ret, nargs, top;
	lua_State *L = (lua_State*) userdata;
	sd_bus *b = sd_bus_message_get_bus(m);
	sd_bus_slot *slot = sd_bus_get_current_slot(b);

	top = lua_gettop(L);

	regtab_get(L, REG_SLOT_TABLE, slot);

	lua_pushvalue(L, 1); /* bus */

	ret = sd_bus_message_is_method_error(m, NULL);

	if (ret) {
		lua_pushstring(L, "__error__");
		const sd_bus_error *e = sd_bus_message_get_error(m);
		if (e) push_sd_bus_error(L, e);
		nargs = 2;
	} else {
		nargs = msg_tolua(L, m, 0);
		if (nargs<0) lua_error(L);
	}

	ret = lua_pcall(L, 1+nargs, 1, 0);

	if (ret != LUA_OK) {
		const char *err = lua_tolstring(L, -1, NULL);
		fprintf(stderr, "error in async callback: %s\n", err?err:"-");
		ret = -1;
	} else {
		ret = lua_tointeger(L, -1);
	}

	lua_settop(L, top);

	return ret;
}

static int lsdbus_call_async(lua_State *L)
{
	int ret;
	uint64_t timeout;
	const char *dest, *path, *intf, *memb, *types;

	sd_bus_slot *slot;
	sd_bus_message *m = NULL;

	sd_bus *b = lua_checksdbus(L, 1);

	luaL_checktype(L, 2, LUA_TFUNCTION);
	dest = luaL_checkservice(L, 3);
	path = luaL_checkpath(L, 4);
	intf = luaL_checkintf(L, 5);
	memb = luaL_checkmember(L, 6);
	types = luaL_optstring(L, 7, NULL);

	ret = sd_bus_message_new_method_call(b, &m, dest, path, intf, memb);

	if (ret < 0)
		luaL_error(L, "%s: failed to create call message: %s",
			   __func__, strerror(-ret));

	if (types != NULL) {
		ret = msg_fromlua(L, m, types, 8);

		if (ret<0)
			goto out;
	}

	ret = sd_bus_get_method_call_timeout(b, &timeout);

	if(ret<0)
		luaL_error(L, "%s: failed to get call timeout: %s", __func__, strerror(-ret));

	ret = sd_bus_call_async(b, &slot, m, method_callback, L, timeout);

out:
	sd_bus_message_unref(m);

	if (ret<0)
		luaL_error(L, "call_async failed: %s", strerror(-ret));

	regtab_store(L,	REG_SLOT_TABLE, slot, 2);
	return lsdbus_slot_push(L, slot, LSDBUS_SLOT_TYPE_ASYNC);
}

static int __lsdbus_testmsg(lua_State *L, int raw)
{
	int ret;
	sd_bus_message *m = NULL;
	const char *types;
	const char *dest = "org.lsdb";
	const char *path = "/lsdb";
	const char *intf = "org.lsdb.test";
	const char *memb = "testmsg";

	sd_bus *b = lua_checksdbus(L, 1);
	types = luaL_optstring(L, 2, NULL);

	ret = sd_bus_message_new_method_call(b, &m, dest, path, intf, memb);

	if (ret < 0)
		luaL_error(L, "%s: failed to create call message: %s",
			   __func__, strerror(-ret));

	if (types!= NULL)
		ret = msg_fromlua(L, m, types, 3);

	if (ret<0)
		goto out;

	sd_bus_message_seal(m, 2, 1000*1000);
#ifdef SDBUS_HAS_DUMP
	sd_bus_message_dump(m, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);
#endif
	sd_bus_message_rewind(m, 1);
	ret = msg_tolua(L, m, raw);

out:
	sd_bus_message_unref(m);

	if(ret<0)
		lua_error(L);

	return ret;
}

static int lsdbus_testmsg(lua_State *L) { return __lsdbus_testmsg(L, 0); }
static int lsdbus_testmsgr(lua_State *L) { return __lsdbus_testmsg(L, 1); }

static int lsdbus_bus_request_name(lua_State *L)
{
	int ret;

	sd_bus *b = lua_checksdbus(L, 1);
	const char *name = luaL_checkservice(L, 2);

	ret = sd_bus_request_name(b, name, 0);

	if (ret<0)
		luaL_error(L, "requesting name %s failed: %s", name, strerror(-ret));

	return 0;
}

static int lsdbus_bus_release_name(lua_State *L)
{
	int ret;

	sd_bus *b = lua_checksdbus(L, 1);
	const char *name = luaL_checkservice(L, 2);

	ret = sd_bus_release_name(b, name);

	if (ret<0)
		luaL_error(L, "releasing name %s failed: %s", name, strerror(-ret));

	return 0;
}


static int lsdbus_bus_state(lua_State *L)
{
	int open, ready;

	sd_bus *b = lua_checksdbus(L, 1);

	open = sd_bus_is_open(b);
	lua_pushboolean(L, open);

	ready = sd_bus_is_ready(b);
	lua_pushboolean(L, ready);

	return 2;
}

static int lsdbus_bus_tostring(lua_State *L)
{
	struct lsdbus_bus *lsdbus =
		(struct lsdbus_bus*) luaL_checkudata(L, 1, BUS_MT);

	lua_pushfstring(L, "bus <%p> [def:%d]",
			lsdbus->b, lsdbus->flags&LSDBUS_BUS_IS_DEFAULT?1:0);
	return 1;
}

static int lsdbus_bus_set_method_call_timeout(lua_State *L)
{
	int ret;
	sd_bus *b = lua_checksdbus(L, 1);
	uint64_t timeout = lua_tointeger(L, 2);

	ret = sd_bus_set_method_call_timeout(b,	timeout);

	if (ret<0)
		luaL_error(L, "set_method_call_timeout failed: %s", strerror(-ret));

	return 0;
}

static int lsdbus_bus_get_method_call_timeout(lua_State *L)
{
	int ret;
	uint64_t timeout;
	sd_bus *b = lua_checksdbus(L, 1);

	ret = sd_bus_get_method_call_timeout(b,	&timeout);

	if (ret<0)
		luaL_error(L, "get_method_call_timeout failed: %s", strerror(-ret));

	lua_pushinteger(L, timeout);
	return 1;
}

static int lsdbus_bus_gc(lua_State *L)
{
	struct lsdbus_bus *lsdbus = (struct lsdbus_bus*) luaL_checkudata(L, 1, BUS_MT);

	if ((lsdbus->flags & LSDBUS_BUS_IS_DEFAULT)) {
		sd_bus_flush(lsdbus->b);
		sd_bus_unref(lsdbus->b);
	} else {
		evl_cleanup(lsdbus->b);
		sd_bus_flush_close_unref(lsdbus->b);
	}

	lua_pushnil(L);
	lua_setmetatable(L, 1);

	return 0;
}

static const luaL_Reg lsdbus_f [] = {
	{ "open", lsdbus_open },
	/* { "testmsg_tolua", lsdbus_testmsg_tolua }, */
	{ NULL, NULL },
};

static const luaL_Reg lsdbus_bus_m [] = {
	{ "get_method_call_timeout", lsdbus_bus_get_method_call_timeout },
	{ "set_method_call_timeout", lsdbus_bus_set_method_call_timeout },
	{ "call", lsdbus_bus_call },
	{ "callr", lsdbus_bus_callr },
	{ "call_async", lsdbus_call_async },
	{ "match_signal", lsdbus_match_signal },
	{ "match", lsdbus_match },
	{ "add_object_vtable", lsdbus_add_object_vtable },
	{ "emit_properties_changed", lsdbus_emit_prop_changed },
	{ "emit_signal", lsdbus_emit_signal },
	{ "context", lsdbus_context },
	{ "loop", evl_loop },
	{ "run", evl_run },
	{ "get_fd", evl_get_fd },
	{ "exit_loop", evl_exit },
	{ "add_signal", evl_add_signal },
	{ "add_periodic", evl_add_periodic },
	{ "add_io", evl_add_io },
	{ "add_child", evl_add_child },
	{ "request_name", lsdbus_bus_request_name },
	{ "release_name", lsdbus_bus_release_name },
	{ "testmsg", lsdbus_testmsg },
	{ "testmsgr", lsdbus_testmsgr },
	{ "state", lsdbus_bus_state },
	{ "__tostring", lsdbus_bus_tostring },
	{ "__gc", lsdbus_bus_gc },
#if LUA_VERSION_NUM >= 504
	{ "__close", lsdbus_bus_gc },
#endif
	{ NULL, NULL },
};

/* borrowed from https://github.com/hoelzro/linotify.git,
   License MIT */
#define register_constant(s)\
    lua_pushinteger(L, s);\
    lua_setfield(L, -2, #s);

int luaopen_lsdbus_core(lua_State *L)
{
	luaL_newmetatable(L, BUS_MT);
	lua_pushvalue(L, -1);
	lua_setfield(L, -1, "__index");
	luaL_setfuncs(L, lsdbus_bus_m, 0);

	luaL_newmetatable(L, EVSRC_MT);
	lua_pushvalue(L, -1);
	lua_setfield(L, -1, "__index");
	luaL_setfuncs(L, lsdbus_evsrc_m, 0);

	luaL_newmetatable(L, SLOT_MT);
	lua_pushvalue(L, -1);
	lua_setfield(L, -1, "__index");
	luaL_setfuncs(L, lsdbus_slot_m, 0);

	luaL_newmetatable(L, VARIANT_MT);
	luaL_newmetatable(L, ARRAY_MT);
	luaL_newmetatable(L, STRUCT_MT);

	lua_settop(L, 1);

	/* create REG_VTAB_USER_ARG reg table as a weak value table */
	init_reg_vtab_user(L);

	luaL_newlib(L, lsdbus_f);

	/* constants */
	register_constant(EPOLLIN);
	register_constant(EPOLLOUT);
	register_constant(EPOLLRDHUP);
	register_constant(EPOLLPRI);
	register_constant(EPOLLET);
	register_constant(EPOLLERR);

	register_constant(SD_EVENT_OFF);
	register_constant(SD_EVENT_ON);
	register_constant(SD_EVENT_ONESHOT);

	register_constant(SIGTERM);
	register_constant(SIGINT);
	register_constant(SIGUSR1);
	register_constant(SIGUSR2);
	register_constant(SIGHUP);

	register_constant(WEXITED);
	register_constant(WSTOPPED);
	register_constant(WCONTINUED);

	/* siginfo_t.si_code */
	register_constant(CLD_EXITED);
	register_constant(CLD_KILLED);
	register_constant(CLD_DUMPED);
	register_constant(CLD_STOPPED);
	register_constant(CLD_TRAPPED);
	register_constant(CLD_CONTINUED);

	return 1;
};
