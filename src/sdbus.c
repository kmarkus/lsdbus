#include <stdio.h>
#include <systemd/sd-bus.h>

#include "lua.h"
#include "lauxlib.h"

#define BUS_MT		"lsdbus.bus"
#define MSG_MT	 	"lsdbus.msg"

/* toplevel functions */
static int lsdbus_open(lua_State *L)
{
	int ret;
	sd_bus **b;
	void *ud;

	b = (sd_bus**) lua_newuserdata(L, sizeof(sd_bus*));

	ret = sd_bus_default_system(b);
	if (ret<0)
		luaL_error(L, "%s: failed to connect to bus: %s",
			   __func__, strerror(-ret));

	luaL_getmetatable(L, BUS_MT);
	lua_setmetatable(L, -2);
	return 1;
}

/* message */
static int msg_fromlua(lua_State *L, const char *type, sd_bus_message* m, int stackpos)
{
	/* sd_bus_message_append(m, ""); */
}

static int msg_tolua(lua_State *L, sd_bus_message *m)
{
	return 0;
}

/* bus methods */
static int lsdbus_bus_call(lua_State *L)
{
	int ret;
	const char *dest, *path, *intf, *memb, *types;

	sd_bus_error error = SD_BUS_ERROR_NULL;
	sd_bus_message *m = NULL;
	sd_bus_message *reply = NULL;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));

	dest = luaL_checkstring(L, 2);
	path = luaL_checkstring(L, 3);
	intf = luaL_checkstring(L, 4);
	memb = luaL_checkstring(L, 5);
	types = luaL_checkstring(L, 6);

	printf("dest: %s\npath: %s\nintf: %s\nmemb: %s\ntypes: %s\n", dest, path, intf, memb, types);

	ret = sd_bus_message_new_method_call(b, &m, dest, path, intf, memb);

	if (ret < 0)
		luaL_error(L, "%s: failed to create call message: %s",
			   __func__, strerror(-ret));

	ret = msg_fromlua(L, NULL, m, 7);
	sd_bus_message_dump(m, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);

	ret = sd_bus_call(b, m, -1, &error, &reply);

	if (ret<0)
		luaL_error(L, "%s call failed: %s", __func__, strerror(-ret));

	sd_bus_message_dump(reply, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);

	sd_bus_error_free(&error);
	sd_bus_message_unref(m);
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


static int lsdbus_bus_gc(lua_State *L)
{
	sd_bus *b = *((sd_bus**) lua_touserdata(L, 1));
	sd_bus_unref(b);
}

static const luaL_Reg lsdbus_f [] = {
	{ "open", lsdbus_open },
	{ NULL, NULL },
};

static const luaL_Reg lsdbus_bus_m [] = {
	{ "call", lsdbus_bus_call },
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
