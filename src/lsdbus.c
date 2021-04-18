#include <stdio.h>
#include <systemd/sd-bus.h>
#include <assert.h>
#include <errno.h>

#include "lua.h"
#include "lauxlib.h"

#define BUS_MT		"lsdbus.bus"
#define MSG_MT	 	"lsdbus.msg"

#define dbg(fmt, args...) ( fprintf(stderr, "%s: ", __FUNCTION__), \
			    fprintf(stderr, fmt, ##args),	   \
			    fprintf(stderr, "\n") )

/* toplevel functions */
static int lsdbus_open(lua_State *L)
{
	int ret;
	sd_bus **b;

	b = (sd_bus**) lua_newuserdata(L, sizeof(sd_bus*));

	ret = sd_bus_open_system(b);
	if (ret<0)
		luaL_error(L, "%s: failed to connect to bus: %s",
			   __func__, strerror(-ret));

	luaL_getmetatable(L, BUS_MT);
	lua_setmetatable(L, -2);
	return 1;
}

/**
 * table_explode - unpack the table at src onto the top of the stack
 */
static int table_explode(lua_State *L, int pos, const char *ctx)
{
	int len, type;

	pos = lua_absindex(L, pos);
	type = lua_type(L, pos);

	if (type != LUA_TTABLE) {
		lua_pushfstring(
			L, "msg_fromlua: error at %s: arg %d not a table but %s",
			ctx, pos, lua_typename(L, type));
		return -1;
	}

	lua_len(L, pos);
	len = lua_tointeger(L, -1);
	lua_pop(L, 1);

	for (int i=1; i<=len; i++) {
		lua_geti(L, pos, i);
		dbg("pushed %s value", lua_typename(L, lua_type(L, -1)));
	}

	lua_remove(L, pos);
	return len;
}

#define BUS_CONTAINER_DEPTH 128


#include <stdbool.h>

#define ELEMENTSOF(x)                                                   \
        (__builtin_choose_expr(                                         \
                !__builtin_types_compatible_p(typeof(x), typeof(&*(x))), \
                sizeof(x)/sizeof((x)[0]),                               \
                (void)0))

#define assert_return(expr, r) do { } while (0)

typedef struct {
        const char *types;
        unsigned n_struct;
        unsigned n_array;
	int stackpos;
} TypeStack;

static int type_stack_push(TypeStack *stack,
			   unsigned max,
			   unsigned *i,
			   const char *types,
			   unsigned n_struct,
			   unsigned n_array,
			   int stackpos) {
        assert(stack);
        assert(max > 0);

        if (*i >= max)
                return -EINVAL;

        stack[*i].types = types;
        stack[*i].n_struct = n_struct;
        stack[*i].n_array = n_array;
	stack[*i].stackpos = stackpos;
        (*i)++;

        return 0;
}

static int type_stack_pop(TypeStack *stack,
			  unsigned max,
			  unsigned *i,
			  const char **types,
			  unsigned *n_struct,
			  unsigned *n_array,
			  int *stackpos) {
        assert(stack);
        assert(max > 0);
        assert(types);
        assert(n_struct);
        assert(n_array);
        assert(stackpos);

        if (*i <= 0)
                return 0;

        (*i)--;
        *types = stack[*i].types;
        *n_struct = stack[*i].n_struct;
        *n_array = stack[*i].n_array;
	*stackpos = stack[*i].stackpos;

        return 1;
}

bool bus_type_is_basic(char c) {
        static const char valid[] = {
                SD_BUS_TYPE_BYTE,
                SD_BUS_TYPE_BOOLEAN,
                SD_BUS_TYPE_INT16,
                SD_BUS_TYPE_UINT16,
                SD_BUS_TYPE_INT32,
                SD_BUS_TYPE_UINT32,
                SD_BUS_TYPE_INT64,
                SD_BUS_TYPE_UINT64,
                SD_BUS_TYPE_DOUBLE,
                SD_BUS_TYPE_STRING,
                SD_BUS_TYPE_OBJECT_PATH,
                SD_BUS_TYPE_SIGNATURE,
                SD_BUS_TYPE_UNIX_FD
        };

        return !!memchr(valid, c, sizeof(valid));
}

static int signature_element_length_internal(
                const char *s,
                bool allow_dict_entry,
                unsigned array_depth,
                unsigned struct_depth,
                size_t *l) {

        int r;

        if (!s)
                return -EINVAL;

        assert(l);

        if (bus_type_is_basic(*s) || *s == SD_BUS_TYPE_VARIANT) {
                *l = 1;
                return 0;
        }

        if (*s == SD_BUS_TYPE_ARRAY) {
                size_t t;

                if (array_depth >= 32)
                        return -EINVAL;

                r = signature_element_length_internal(s + 1, true, array_depth+1, struct_depth, &t);
                if (r < 0)
                        return r;

                *l = t + 1;
                return 0;
        }

        if (*s == SD_BUS_TYPE_STRUCT_BEGIN) {
                const char *p = s + 1;

                if (struct_depth >= 32)
                        return -EINVAL;

                while (*p != SD_BUS_TYPE_STRUCT_END) {
                        size_t t;

                        r = signature_element_length_internal(p, false, array_depth, struct_depth+1, &t);
                        if (r < 0)
                                return r;

                        p += t;
                }

                if (p - s < 2)
                        /* D-Bus spec: Empty structures are not allowed; there
                         * must be at least one type code between the parentheses.
                         */
                        return -EINVAL;

                *l = p - s + 1;
                return 0;
        }

        if (*s == SD_BUS_TYPE_DICT_ENTRY_BEGIN && allow_dict_entry) {
                const char *p = s + 1;
                unsigned n = 0;

                if (struct_depth >= 32)
                        return -EINVAL;

                while (*p != SD_BUS_TYPE_DICT_ENTRY_END) {
                        size_t t;

                        if (n == 0 && !bus_type_is_basic(*p))
                                return -EINVAL;

                        r = signature_element_length_internal(p, false, array_depth, struct_depth+1, &t);
                        if (r < 0)
                                return r;

                        p += t;
                        n++;
                }

                if (n != 2)
                        return -EINVAL;

                *l = p - s + 1;
                return 0;
        }

        return -EINVAL;
}

int signature_element_length(const char *s, size_t *l) {
        return signature_element_length_internal(s, true, 0, 0, l);
}

int msg_fromlua(lua_State *L, sd_bus_message *m, const char *types, int stpos)
{
        unsigned n_array, n_struct;
        TypeStack stack[BUS_CONTAINER_DEPTH];
        unsigned stack_ptr = 0;
        int r;

        assert_return(m, -EINVAL);
        assert_return(types, -EINVAL);
        assert_return(!m->sealed, -EPERM);
        assert_return(!m->poisoned, -ESTALE);

        n_array = (unsigned) -1;
        n_struct = strlen(types);

        for (;;) {
                const char *t;

                if (n_array == 0 || (n_array == (unsigned) -1 && n_struct == 0)) {
                        r = type_stack_pop(stack, ELEMENTSOF(stack), &stack_ptr, &types, &n_struct, &n_array, &stpos);
                        if (r < 0)
                                return r;
                        if (r == 0)
                                break;

                        r = sd_bus_message_close_container(m);
                        if (r < 0)
                                return r;

                        continue;
                }

                t = types;
                if (n_array != (unsigned) -1)
                        n_array--;
                else {
                        types++;
                        n_struct--;
                }

                switch (*t) {

                case SD_BUS_TYPE_BYTE: {
			uint8_t x;
			x = luaL_checkinteger(L, stpos);
			dbg("adding BYTE %c", x);
			r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
			break;
                }

                case SD_BUS_TYPE_BOOLEAN:
                case SD_BUS_TYPE_INT32:
                case SD_BUS_TYPE_UINT32:
                case SD_BUS_TYPE_UNIX_FD: {
                        uint32_t x;
			static_assert(sizeof(int32_t) == sizeof(int));
			x = luaL_checkinteger(L, stpos);
			dbg("adding BOOL/uint/int/fd %u", x);
			r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_INT16:
                case SD_BUS_TYPE_UINT16: {
                        uint16_t x;
			x = luaL_checkinteger(L, stpos);
			dbg("adding UINT16 %u", x);
                        r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_INT64:
                case SD_BUS_TYPE_UINT64: {
                        uint64_t x;
			x = luaL_checkinteger(L, stpos);
			dbg("adding UINT64 %lu", x);
                        r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_DOUBLE: {
                        double x;
			x = luaL_checknumber(L, stpos);
			dbg("adding DOUBLE %f", x);
                        r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_STRING:
                case SD_BUS_TYPE_OBJECT_PATH:
                case SD_BUS_TYPE_SIGNATURE: {
                        const char *x =	luaL_checkstring(L, stpos);
			dbg("adding string %s", x);
                        r = sd_bus_message_append_basic(m, *t, x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_ARRAY: {
                        size_t k;

                        r = signature_element_length(t + 1, &k);
                        if (r < 0)
                                return r;
                        {
                                char s[k + 1];
                                memcpy(s, t + 1, k);
                                s[k] = 0;

                                r = sd_bus_message_open_container(m, SD_BUS_TYPE_ARRAY, s);
                                if (r < 0)
                                        return r;
                        }

                        if (n_array == (unsigned) -1) {
                                types += k;
                                n_struct -= k;
                        }

                        r = type_stack_push(stack, ELEMENTSOF(stack), &stack_ptr, types, n_struct, n_array, stpos);
                        if (r < 0)
                                return r;

                        types = t + 1;
                        n_struct = k;

			/* first array param is size of array */
                        /* n_array = va_arg(ap, unsigned); */
			r = table_explode(L, stpos, types-1);
			if (r<0)
				return r;
			n_array = r;
			dbg("found array of size %u", r);
			stpos =	lua_absindex(L,	-r);
                        break;
                }

                case SD_BUS_TYPE_VARIANT: {
                        const char *s;

                        /* s = va_arg(ap, const char*);
                        if (!s)
                                return -EINVAL;
			*/

                        r = sd_bus_message_open_container(m, SD_BUS_TYPE_VARIANT, s);
                        if (r < 0)
                                return r;

                        r = type_stack_push(stack, ELEMENTSOF(stack), &stack_ptr, types, n_struct, n_array, stpos);
                        if (r < 0)
                                return r;

                        types = s;
                        n_struct = strlen(s);
                        n_array = (unsigned) -1;

                        break;
                }

                case SD_BUS_TYPE_STRUCT_BEGIN:
                case SD_BUS_TYPE_DICT_ENTRY_BEGIN: {
                        size_t k;

                        r = signature_element_length(t, &k);
                        if (r < 0)
                                return r;

                        {
                                char s[k - 1];

                                memcpy(s, t + 1, k - 2);
                                s[k - 2] = 0;

                                r = sd_bus_message_open_container(m, *t == SD_BUS_TYPE_STRUCT_BEGIN ? SD_BUS_TYPE_STRUCT : SD_BUS_TYPE_DICT_ENTRY, s);
                                if (r < 0)
                                        return r;
                        }

                        if (n_array == (unsigned) -1) {
                                types += k - 1;
                                n_struct -= k - 1;
                        }

                        r = type_stack_push(stack, ELEMENTSOF(stack), &stack_ptr, types, n_struct, n_array, stpos);
                        if (r < 0)
                                return r;

                        types = t + 1;
                        n_struct = k - 2;
                        n_array = (unsigned) -1;

                        break;
                }

                default:
                        r = -EINVAL;
                }

                if (r < 0)
                        return r;
        }

        return 1;
}

#if 0
/**
 * append Lua values conforming to the given types string to a message
 *
 * @L Lua state
 * @m message
 * @t type string
 * @stpos stack index with next Lua value to append to m
 * @tpos index into t with next argument to be pushed on the stack
 *
 * @return 0 if OK, <0 in case of error. In that case, an error
 * message is pushed to the top of the stack.
 */
static int __msg_append(lua_State *L, sd_bus_message* m, char *t, int stpos, int stend, int tpos)
{
	int ret = 0;
	char ttmp[strlen(t)];

	printf("t=%s, stpos=%i\n", t, stpos);

	for (;t[tpos] != '\0'; tpos++, stpos++) {
		switch(t[tpos]) {
		case SD_BUS_TYPE_BOOLEAN:
		case SD_BUS_TYPE_INT32:
		case SD_BUS_TYPE_UINT32:
		case SD_BUS_TYPE_UNIX_FD: {
			uint32_t x;
			static_assert(sizeof(int32_t) == sizeof(int));
			x = luaL_checkinteger(L, stpos);
			ret = sd_bus_message_append_basic(m, *t, &x);
			break;
		}
                case SD_BUS_TYPE_BYTE: {
			uint8_t x;
			x = luaL_checkinteger(L, stpos);
			ret = sd_bus_message_append_basic(m, *t, &x);
			break;
		}
                case SD_BUS_TYPE_INT16:
                case SD_BUS_TYPE_UINT16: {
                        uint16_t x;
			x = luaL_checkinteger(L, stpos);
                        ret = sd_bus_message_append_basic(m, *t, &x);
                        break;
                }
                case SD_BUS_TYPE_INT64:
                case SD_BUS_TYPE_UINT64: {
                        uint64_t x;
			x = luaL_checkinteger(L, stpos);
                        ret = sd_bus_message_append_basic(m, *t, &x);
                        break;
                }
                case SD_BUS_TYPE_DOUBLE: {
                        double x;
			x = luaL_checknumber(L, stpos);
                        ret = sd_bus_message_append_basic(m, *t, &x);
                        break;
                }
                case SD_BUS_TYPE_STRING:
                case SD_BUS_TYPE_OBJECT_PATH:
                case SD_BUS_TYPE_SIGNATURE: {
                        const char *x =	luaL_checkstring(L, stpos);
                        ret = sd_bus_message_append_basic(m, *t, x);
                        break;
                }
                case SD_BUS_TYPE_VARIANT: {
			ret = -ENOTSUP;
			break;
		}
                case SD_BUS_TYPE_ARRAY: {
			luaL_checktype(L, stpos, LUA_TTABLE);
			/* extract container_substring */
			int top;
			/* tbd. int len = cont_type(t[tpos+1], ttmp); */

			ret = sd_bus_message_open_container(m, 'a', ttmp);

			if (ret < 0)
				return ret;

			lua_pushnil(L);
			top = lua_gettop(L);
			while (lua_next(L, stpos) != 0) {
				__msg_append(L, m, ttmp, top, top+1);
				lua_pop(L, 1);
			}

			tpos+=len-1;

			ret = sd_bus_message_close_container(m);
			break;

		}
                case SD_BUS_TYPE_STRUCT_BEGIN:
                case SD_BUS_TYPE_DICT_ENTRY_BEGIN: {
			/* ret = sd_bus_message_open_container( */
			/* 	m, SD_BUS_TYPE_STRUCT_BEGIN ? SD_BUS_TYPE_STRUCT */
			/* 	: SD_BUS_TYPE_DICT_ENTRY, s); */
			/* if (ret < 0) */
			/* 	break; */
			ret = -ENOTSUP;
			break
		}
		default:
			ret = -EINVAL;
		}

		if (ret != 0)
			break; /* loop */
	};

	if (*t == '\0' && stpos != endpos) {
		lua_pushstring(L, "too many arguments provided");
		ret = -EINVAL;
	}

	if (*t != '\0' && stpos == endpos) {
		lua_pushstring(L, "missing arg for arg %c at pos %d", ...);
		ret = -EINVAL;
	}

	return ret;
}

static int msg_append(lua_State *L, sd_bus_message* m, char *t, int stpos)
{
	return  __msg_append(L, m, t, stpos, lua_gettop(L) + 1);
}
#endif

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
	types = luaL_optstring(L, 6, NULL);

	printf("2 dest:  %s\n3 path:  %s\n4 intf:  %s\n5 memb:  %s\n6 types:  %s\n",
	       dest, path, intf, memb, types);

	ret = sd_bus_message_new_method_call(b, &m, dest, path, intf, memb);

	if (ret < 0)
		luaL_error(L, "%s: failed to create call message: %s",
			   __func__, strerror(-ret));

	if (types!= NULL)
		ret = msg_fromlua(L, m, types, 7);

	if (ret<0)
		return -1;

	printf("c\n");

	sd_bus_message_seal(m, 2, 1000*1000);
	sd_bus_message_dump(m, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);

	ret = sd_bus_call(b, m, -1, &error, &reply);

	if (ret<0)
		luaL_error(L, "%s error: %s", __func__, strerror(-ret));

	/* msg_tolua(L, reply); */
	sd_bus_message_dump(reply, stdout, SD_BUS_MESSAGE_DUMP_WITH_HEADER);

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
