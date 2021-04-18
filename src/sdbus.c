#include <stdio.h>
#include <systemd/sd-bus.h>
#include <assert.h>
#include <errno.h>

#include "lua.h"
#include "lauxlib.h"

#define BUS_MT		"lsdbus.bus"
#define MSG_MT	 	"lsdbus.msg"

/* toplevel functions */
static int lsdbus_open(lua_State *L)
{
	int ret;
	sd_bus **b;

	b = (sd_bus**) lua_newuserdata(L, sizeof(sd_bus*));

	ret = sd_bus_default(b);
	if (ret<0)
		luaL_error(L, "%s: failed to connect to bus: %s",
			   __func__, strerror(-ret));

	luaL_getmetatable(L, BUS_MT);
	lua_setmetatable(L, -2);
	return 1;
}

/* message */
static int msg_fromlua(lua_State *L,
		       sd_bus_message* m,
		       const char *types,
		       int startpos)
{
	const char* t;
	int ret;
	int pos = startpos;
	int endpos = lua_gettop(L) + 1;
	printf("types=%s, pos=%i, endpos=%i\n",	types, pos, endpos);

	for (t = types; *t != '\0' && pos<endpos; t++, pos++) {
		switch(*t) {
		case SD_BUS_TYPE_BOOLEAN:
		case SD_BUS_TYPE_INT32:
		case SD_BUS_TYPE_UINT32:
		case SD_BUS_TYPE_UNIX_FD: {
			uint32_t x;
			static_assert(sizeof(int32_t) == sizeof(int));
			x = luaL_checkinteger(L, pos);
			ret = sd_bus_message_append_basic(m, *t, &x);
			break;
		}
                case SD_BUS_TYPE_BYTE: {
			uint8_t x;
			x = luaL_checkinteger(L, pos);
			ret = sd_bus_message_append_basic(m, *t, &x);
			break;
		}
                case SD_BUS_TYPE_INT16:
                case SD_BUS_TYPE_UINT16: {
                        uint16_t x;
			x = luaL_checkinteger(L, pos);
                        ret = sd_bus_message_append_basic(m, *t, &x);
                        break;
                }
                case SD_BUS_TYPE_INT64:
                case SD_BUS_TYPE_UINT64: {
                        uint64_t x;
			x = luaL_checkinteger(L, pos);
                        ret = sd_bus_message_append_basic(m, *t, &x);
                        break;
                }
                case SD_BUS_TYPE_DOUBLE: {
                        double x;
			x = luaL_checknumber(L, pos);
                        ret = sd_bus_message_append_basic(m, *t, &x);
                        break;
                }
                case SD_BUS_TYPE_STRING:
                case SD_BUS_TYPE_OBJECT_PATH:
                case SD_BUS_TYPE_SIGNATURE: {
                        const char *x =	luaL_checkstring(L, pos);
                        ret = sd_bus_message_append_basic(m, *t, x);
                        break;
                }
                case SD_BUS_TYPE_VARIANT: {
		}
                case SD_BUS_TYPE_ARRAY: {
		}
                case SD_BUS_TYPE_STRUCT_BEGIN:
                case SD_BUS_TYPE_DICT_ENTRY_BEGIN: {
		}
		default:
			return -EINVAL;
		}

		if (ret != 0) {
			sd_bus_message_unref(m);
			luaL_error(L, "failed to append %c", *t);
		}
	};

	if (*t == '\0' && pos != endpos) {
		sd_bus_message_unref(m);
		luaL_error(L, "too many message args, got %I, expected %I",
			   endpos - startpos, pos - startpos);
	}

	if (*t != '\0' && pos == endpos) {
		sd_bus_message_unref(m);
		luaL_error(L, "too few message args, got %I, expected %I",
			   endpos - startpos, pos - startpos);
	}

	return 0;
}

static int msg_tolua(lua_State *L, sd_bus_message *m)
{
	sd_bus_message_dump(m, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);
	lua_pushboolean(L, 1);
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
	types = lua_tolstring(L, 6, NULL);

	printf("dest:  %s\npath:  %s\nintf:  %s\nmemb:  %s\ntypes:  %s\n",
	       dest, path, intf, memb, types);

	ret = sd_bus_message_new_method_call(b, &m, dest, path, intf, memb);

	if (ret < 0)
		luaL_error(L, "%s: failed to create call message: %s",
			   __func__, strerror(-ret));

	if (types!= NULL)
		ret = msg_fromlua(L, m, types, 7);

	sd_bus_message_seal(m, 2, 1000*1000);
	sd_bus_message_dump(m, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);

	ret = sd_bus_call(b, m, -1, &error, &reply);

	if (ret<0)
		luaL_error(L, "%s error: %s", __func__, strerror(-ret));

	msg_tolua(L, reply);

	sd_bus_error_free(&error);
	sd_bus_message_unref(reply);
	sd_bus_message_unref(m);
	return 1;
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
	return 0;
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
