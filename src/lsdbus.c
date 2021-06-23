#include <signal.h>
#include "lsdbus.h"

static const char *const open_opts_lst [] = {
	"default",
	"system",
	"user",
	"default_system",
	"default_user",
	NULL
};

static int(*open_funcs[])(sd_bus **bus) = {
	sd_bus_default,
	sd_bus_open_system,
	sd_bus_open_user,
	sd_bus_default_system,
	sd_bus_default_user,
};


/**
 * store a function in registry.regtab[k] = fun
 *
 * if the regtab doesn't exist, create it.
 */
void regtab_store(lua_State *L, const char* regtab, void *k, int funidx)
{
	if (lua_getfield(L, LUA_REGISTRYINDEX, regtab) != LUA_TTABLE) {
		lua_pop(L, 1);
		lua_newtable(L);
		lua_setfield(L, LUA_REGISTRYINDEX, regtab);
		lua_getfield(L, LUA_REGISTRYINDEX, regtab);
	}

	lua_pushvalue(L, funidx);
	lua_rawsetp(L, -2, k);
}

/**
 * push the value regtab[k] onto the top of the stack
 *
 * @return returns the type of the value
 */
int regtab_get(lua_State *L, const char* regtab, void *k)
{
	if (lua_getfield(L, LUA_REGISTRYINDEX, regtab) != LUA_TTABLE)
		luaL_error(L, "missing registry table %s", regtab);

	return lua_rawgetp(L, -1, k);
}


/* toplevel functions */
static int lsdbus_open(lua_State *L)
{
	int ret;
	sd_bus **b;

	ret = luaL_checkoption(L, 1, "default", open_opts_lst);

	dbg("opening %s bus connection", open_opts_lst[ret]);

	b = (sd_bus**) lua_newuserdata(L, sizeof(sd_bus*));

	ret = open_funcs[ret](b);

	if (ret<0)
		luaL_error(L, "%s: failed to connect to bus: %s",
			   __func__, strerror(-ret));

	luaL_getmetatable(L, BUS_MT);
	lua_setmetatable(L, -2);
	return 1;
}

/* bus methods */
static int lsdbus_bus_call(lua_State *L)
{
	int ret;
	uint64_t timeout;
	const char *dest, *path, *intf, *memb, *types;

	sd_bus_error error = SD_BUS_ERROR_NULL;
	sd_bus_message *m = NULL;
	sd_bus_message *reply = NULL;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));

	dest = luaL_checkstring(L, 2);
	path = luaL_checkstring(L, 3);
	intf = luaL_checkstring(L, 4);
	memb = luaL_checkstring(L, 5);
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

	sd_bus_message_seal(m, 2, timeout);

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
	ret = msg_tolua(L, reply);

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
int signal_callback(sd_bus_message *m, void *userdata, sd_bus_error *ret_error)
{
	(void)ret_error;
	int ret, nargs;
	lua_State *L = (lua_State*) userdata;
	sd_bus *b = sd_bus_message_get_bus(m);
	sd_bus_slot *slot = sd_bus_get_current_slot(b);

	regtab_get(L, REG_SLOT_TABLE, slot);

	push_string_or_nil(L, sd_bus_message_get_sender(m));
	push_string_or_nil(L, sd_bus_message_get_path(m));
	push_string_or_nil(L, sd_bus_message_get_interface(m));
	push_string_or_nil(L, sd_bus_message_get_member(m));

	nargs = msg_tolua(L, m);

	if(nargs<0)
		lua_error(L);

	lua_call(L, nargs+4, 1);

	ret = lua_tointeger(L, -1);
	lua_settop(L, 0);
	return ret;
}

static int lsdbus_match_signal(lua_State *L)
{
	int ret;
	sd_bus_slot *slot;
	const char *sender=NULL, *path=NULL, *intf=NULL, *memb=NULL;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));

	if (!lua_isnil(L, 2)) sender = luaL_checkstring(L, 2);
	if (!lua_isnil(L, 3)) path = luaL_checkstring(L, 3);
	if (!lua_isnil(L, 4)) intf = luaL_checkstring(L, 4);
	if (!lua_isnil(L, 5)) memb = luaL_checkstring(L, 5);
	luaL_checktype(L, 6, LUA_TFUNCTION);

	ret = sd_bus_match_signal(b, &slot, sender, path, intf, memb, signal_callback, L);

	if (ret<0)
		luaL_error(L, "failed to install signal match rule: %s", strerror(-ret));

	regtab_store(L,	REG_SLOT_TABLE, slot, 6);
	return 0;
}

static int lsdbus_match(lua_State *L)
{
	int ret;
	sd_bus_slot *slot;
	const char *match=NULL;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));

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
	return 0;
}

static int lsdbus_testmsg(lua_State *L)
{
	int ret;
	sd_bus_message *m = NULL;
	const char *types;
	const char *dest = "org.lsdb";
	const char *path = "/lsdb";
	const char *intf = "org.lsdb.test";
	const char *memb = "testmsg";

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
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
	ret = msg_tolua(L, m);

out:
	sd_bus_message_unref(m);

	if(ret<0)
		lua_error(L);

	return ret;
}

static int lsdbus_loop(lua_State *L)
{
	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	evl_loop(L, b);
	return 0;
}



static int lsdbus_bus_tostring(lua_State *L)
{
	int ret;
	sd_id128_t id;
	char s[SD_ID128_STRING_MAX];

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));

	ret = sd_bus_get_bus_id(b, &id);

	if (ret<0)
		luaL_error(L, "%s: failed to get bus id: %s", __func__, strerror(-ret));

	lua_pushstring(L, sd_id128_to_string(id, s));
	return 1;
}

static int lsdbus_bus_set_method_call_timeout(lua_State *L)
{
	int ret;
	sd_bus *b = *((sd_bus**) lua_touserdata(L, -2));
	uint64_t timeout = lua_tointeger(L, -1);

	ret = sd_bus_set_method_call_timeout(b,	timeout);

	if (ret<0)
		luaL_error(L, "set_method_call_timeout failed: %s", strerror(-ret));

	return 0;
}

static int lsdbus_bus_get_method_call_timeout(lua_State *L)
{
	int ret;
	uint64_t timeout;
	sd_bus *b = *((sd_bus**) lua_touserdata(L, 1));

	ret = sd_bus_get_method_call_timeout(b,	&timeout);

	if (ret<0)
		luaL_error(L, "get_method_call_timeout failed: %s", strerror(-ret));

	lua_pushinteger(L, timeout);
	return 1;
}

static int lsdbus_bus_gc(lua_State *L)
{
	sd_bus *b = *((sd_bus**) lua_touserdata(L, 1));
	evl_cleanup(b);
	sd_bus_unref(b);
	return 0;
}

static const luaL_Reg lsdbus_f [] = {
	{ "open", lsdbus_open },
	{ "xml_fromfile", lsdbus_xml_fromfile },
	{ "xml_fromstr", lsdbus_xml_fromstr },
	/* { "testmsg_tolua", lsdbus_testmsg_tolua }, */
	{ NULL, NULL },
};

static const luaL_Reg lsdbus_bus_m [] = {
	{ "get_method_call_timeout", lsdbus_bus_get_method_call_timeout },
	{ "set_method_call_timeout", lsdbus_bus_set_method_call_timeout },
	{ "call", lsdbus_bus_call },
	{ "match_signal", lsdbus_match_signal },
	{ "match", lsdbus_match },
	{ "loop", lsdbus_loop },
	{ "exit_loop", evl_exit },
	{ "add_signal", evl_add_signal },
	{ "testmsg", lsdbus_testmsg },
	{ "__tostring", lsdbus_bus_tostring },
	{ "__gc", lsdbus_bus_gc },
	{ NULL, NULL },
};

int luaopen_lsdbus(lua_State *L)
{
	luaL_newmetatable(L, BUS_MT);
	lua_pushvalue(L, -1);
	lua_setfield(L, -1, "__index");
	luaL_setfuncs(L, lsdbus_bus_m, 0);

	luaL_newlib(L, lsdbus_f);
	return 1;
};
