#include "lsdbus.h"

/**
 * table_explode - unpack the table at src onto the top of the stack
 *
 * @param L
 * @pos relative or absolute stack position of table to unpack
 * @ctx	context to print in case of error
 * @return number of elements unpacked or -1 in case of error.

 * The table is removed from the given stackpos. In the error case, a
 * string with the error message is pushed on top of the stack.
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
		dbg("pushed %s value to pos %i", lua_typename(L, lua_type(L, -1)), pos+i-2);
	}

	lua_remove(L, pos);
	return len;
}

/**
 * dict_explode - unpack the table at src onto the top of the stack
 *
 * this function is identical to the one above except that the table
 * is traversed as a dictionary (pairs) instead of as an array
 * (ipairs). The function returns the sum of keys and values pushed
 * onto the stack.
 */
static int dict_explode(lua_State *L, int pos, const char *ctx)
{
	int len=0, type;

	pos = lua_absindex(L, pos);
	type = lua_type(L, pos);

	if (type != LUA_TTABLE) {
		lua_pushfstring(
			L, "msg_fromlua: error at %s: arg %d not a table but %s",
			ctx, pos, lua_typename(L, type));
		return -1;
	}

	lua_pushnil(L);  /* first key */
	while (lua_next(L, pos) != 0) {
		dbg("pushed %s - %s to pos %i",
		    lua_typename(L, lua_type(L, -2)),
		    lua_typename(L, lua_type(L, -1)), pos+len-1);
		/* duplicate key to top for next iteration */
		lua_pushvalue(L, -2);
		len++;
	}

	lua_remove(L, pos);
	return len*2;
}


int luaL_checkboolean (lua_State *L, int index)
{
	int t = lua_type(L, index);

	if (t != LUA_TBOOLEAN) {
		luaL_error(L, "bad argument #%d (boolean expected, got %s)",
			   index, lua_typename(L, t));
	}
	return lua_toboolean(L, index);
}

int push_sd_bus_error(lua_State* L, const sd_bus_error* err)
{
	if (!err)
		return -1;
	lua_newtable(L);
	lua_pushstring(L, err->name);
	lua_rawseti(L, -2, 1);
	lua_pushstring(L, err->message);
	lua_rawseti(L, -2, 2);
	return 1;
}

/*
 * Copied from lsdbus v248-rc2-173-g275334c562
 */
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

bool bus_type_is_container(char c) {
        static const char valid[] = {
                SD_BUS_TYPE_ARRAY,
                SD_BUS_TYPE_VARIANT,
                SD_BUS_TYPE_STRUCT,
                SD_BUS_TYPE_DICT_ENTRY
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

/**
 * msg_fromlua
 *
 * @param L
 * @param m message to fill with Lua data
 * @types dbus type string
 * @stpos stack position where message data starts
 *
 * All arguments are popped from the stack.
 *
 * @return 0 if OK, <0 if not. In case of error, an error message is
 * pushed to the top of the stack.
 */
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
                        if (r < 0) {
				lua_pushfstring(L, "invalid type string %s, no container to close", types);
                                return r;
			}
                        if (r == 0)
                                break;

                        r = sd_bus_message_close_container(m);
			dbg("sd_bus_message_close_container");
                        if (r < 0) {
				lua_pushfstring(L, "failed to close container %s", strerror(-r));
                                return r;
			}

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
			dbg("append BYTE %c", x);
			r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
			break;
                }

                case SD_BUS_TYPE_BOOLEAN: {
			int x = luaL_checkboolean(L, stpos);
			dbg("append bool %i", x);
			r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
		}

                case SD_BUS_TYPE_INT32:
                case SD_BUS_TYPE_UINT32:
                case SD_BUS_TYPE_UNIX_FD: {
                        uint32_t x;
			static_assert(sizeof(int32_t) == sizeof(int), "int != int32_t");
			x = luaL_checkinteger(L, stpos);
			dbg("append uint/int/fd %u", x);
			r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_INT16:
                case SD_BUS_TYPE_UINT16: {
                        uint16_t x;
			x = luaL_checkinteger(L, stpos);
			dbg("append UINT16 %u", x);
                        r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_INT64:
                case SD_BUS_TYPE_UINT64: {
                        uint64_t x;
			x = luaL_checkinteger(L, stpos);
			dbg("append UINT64 %lu", x);
                        r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_DOUBLE: {
                        double x;
			x = luaL_checknumber(L, stpos);
			dbg("append DOUBLE %f", x);
                        r = sd_bus_message_append_basic(m, *t, &x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_STRING:
                case SD_BUS_TYPE_OBJECT_PATH:
                case SD_BUS_TYPE_SIGNATURE: {
                        const char *x =	luaL_checkstring(L, stpos);
			dbg("append string %s", x);
                        r = sd_bus_message_append_basic(m, *t, x);
			lua_remove(L, stpos);
                        break;
                }

                case SD_BUS_TYPE_ARRAY: {
                        size_t k;

                        r = signature_element_length(t + 1, &k);
                        if (r < 0) {
				lua_pushfstring(L, "invalid array type string %s", t);
                                return r;
			}
                        {
                                char s[k + 1];
                                memcpy(s, t + 1, k);
                                s[k] = 0;

                                r = sd_bus_message_open_container(m, SD_BUS_TYPE_ARRAY, s);
                                if (r < 0) {
					lua_pushfstring(L, "failed to open array container for %s: %s",
							t, strerror(-r));
                                        return r;
				}
                        }

                        if (n_array == (unsigned) -1) {
                                types += k;
                                n_struct -= k;
                        }

                        r = type_stack_push(stack, ELEMENTSOF(stack), &stack_ptr, types, n_struct, n_array, stpos);
                        if (r < 0) {
				lua_pushfstring(L, "container depth %u exceeded", BUS_CONTAINER_DEPTH);
                                return r;
			}

                        types = t + 1;
                        n_struct = k;

			/* first array param is size of array */
                        /* n_array = va_arg(ap, unsigned); */

			if(t[1] == SD_BUS_TYPE_DICT_ENTRY_BEGIN) {
				r = dict_explode(L, stpos, types-1);
				n_array = r/2;

			} else {
				r = table_explode(L, stpos, types-1);
				n_array = r;
			}

			if (r<0)
				return r; /* error msg pushed by _explode function */

			dbg("appending container %c of size %u", t[1], n_array);

			stpos =	lua_absindex(L,	-r);
                        break;
                }

                case SD_BUS_TYPE_VARIANT: {
			const char* s;

			int ltype = lua_type(L, stpos);

			if (ltype != LUA_TTABLE) {
				lua_pushfstring(L, "invalid type %s of arg %i, expected table",
						lua_typename(L,	ltype),	stpos);
				return -EINVAL;
			}

			r = table_explode(L, stpos, s);

			if (r != 2) {
				lua_pushfstring(L, "invalid table at stpos %i", stpos);
				return -EINVAL;
			}

			s = luaL_checkstring(L, -2);
			lua_remove(L, -2);

			dbg("pushing variant of type %s", s);

                        r = sd_bus_message_open_container(m, SD_BUS_TYPE_VARIANT, s);
                        if (r < 0) {
				lua_pushfstring(L, "failed to open variant container for typestr '%s', val: %s: %s", s, t, strerror(-r));
                                return r;
			}

                        r = type_stack_push(stack, ELEMENTSOF(stack), &stack_ptr, types, n_struct, n_array, stpos);
                        if (r < 0) {
				lua_pushfstring(L, "container depth %u exceeded", BUS_CONTAINER_DEPTH);
                                return r;
			}

			types = s;
			n_struct = strlen(s);
			n_array = (unsigned) -1;
			stpos =	lua_absindex(L,	-1);
			dbg("appending variant %s of size %u", types, n_struct);

                        break;
                }

                case SD_BUS_TYPE_STRUCT_BEGIN:
                case SD_BUS_TYPE_DICT_ENTRY_BEGIN: {
                        size_t k;

                        r = signature_element_length(t, &k);
                        if (r < 0) {
				lua_pushfstring(L, "invalid %s type string %s",
						*t == SD_BUS_TYPE_STRUCT_BEGIN ? "struct" : "dict", t);
                                return r;
			}

                        {
                                char s[k - 1];

                                memcpy(s, t + 1, k - 2);
                                s[k - 2] = 0;

                                r = sd_bus_message_open_container(m, *t == SD_BUS_TYPE_STRUCT_BEGIN ? SD_BUS_TYPE_STRUCT : SD_BUS_TYPE_DICT_ENTRY, s);
                                if (r < 0) {
					lua_pushfstring(L, "failed to open %s container for %s: %s",
							*t == SD_BUS_TYPE_STRUCT_BEGIN ? "struct" : "dict",
							t, strerror(-r));

                                        return r;
				}
                        }

                        if (n_array == (unsigned) -1) {
                                types += k - 1;
                                n_struct -= k - 1;
                        }

                        r = type_stack_push(stack, ELEMENTSOF(stack), &stack_ptr, types, n_struct, n_array, stpos);
                        if (r < 0) {
				lua_pushfstring(L, "container depth %u exceeded", BUS_CONTAINER_DEPTH);
                                return r;
			}

                        types = t + 1;
                        n_struct = k - 2;
                        n_array = (unsigned) -1;

			dbg("struct: %c", *t);
			if (*t == SD_BUS_TYPE_STRUCT_BEGIN) {
				r = table_explode(L, stpos, t);
				if (r<0) {
					return r;
				}
				stpos =	lua_absindex(L,	-r);
			}

                        break;
                }

                default:
			lua_pushfstring(L, "invalid or unexpected typestring '%c'", *t);
                        r = -EINVAL;
                }

                if (r < 0)
                        return r;
        }

	return 1;
}

static int __msg_tolua(lua_State *L, sd_bus_message* m, char ctype)
{
	int r;

        for (;;) {
                /* _cleanup_free_ char *prefix = NULL; */
                const char *contents = NULL;
                char type;
                union {
                        uint8_t u8;
                        uint16_t u16;
                        int16_t s16;
                        uint32_t u32;
                        int32_t s32;
                        uint64_t u64;
                        int64_t s64;
                        double d64;
			const char *string;
                        int i;
                } basic;

                r = sd_bus_message_peek_type(m, &type, &contents);

                if (r < 0)
                        luaL_error(L, "msg_tolua: peek_type failed: %s", strerror(-r));

                if (r == 0) {
			if(ctype==0)
				return 0;

                        r = sd_bus_message_exit_container(m);
                        if (r < 0)
				luaL_error(L, "msg_tolua: failed to exit container: %s", strerror(-r));

			dbg("exit container ctype %c", ctype);
                        return 0;
                }

		if (type == SD_BUS_TYPE_ARRAY || type == SD_BUS_TYPE_STRUCT) {
			dbg("enter ARRAY/STRUCT container: %c", type);

                        r = sd_bus_message_enter_container(m, type, contents);

                        if (r < 0)
				luaL_error(L, "msg_tolua: failed to enter container: %s", strerror(-r));

			lua_newtable(L);
			__msg_tolua(L, m, type);
			goto update_table;

		} else if (type == SD_BUS_TYPE_DICT_ENTRY) {
			dbg("enter DICT_ENTRY container: %c", type);

                        r = sd_bus_message_enter_container(m, type, contents);

                        if (r < 0)
				luaL_error(L, "msg_tolua: failed to enter container: %s", strerror(-r));

			__msg_tolua(L, m, type);
			dbg("rawset into parent at -3");
			lua_rawset(L, -3);
			continue;

		} else if (type == SD_BUS_TYPE_VARIANT) {
			dbg("enter VARIANT container: %c", type);

			r = sd_bus_message_enter_container(m, type, contents);

                        if (r < 0)
				luaL_error(L, "msg_tolua: failed to enter container: %s", strerror(-r));

			__msg_tolua(L, m, type);
			continue;
		}

                r = sd_bus_message_read_basic(m, type, &basic);
                if (r < 0)
			luaL_error(L, "msg_tolua: read_basic error: %s", strerror(-r));

                assert(r > 0);

                switch (type) {
                case SD_BUS_TYPE_BYTE:
			dbg("push BYTE");
			lua_pushinteger(L, basic.u8);
                        break;

                case SD_BUS_TYPE_BOOLEAN:
			dbg("push BOOLEAN");
			lua_pushboolean(L, basic.i);
                        break;

                case SD_BUS_TYPE_INT16:
			dbg("push INT16");
			lua_pushinteger(L, basic.s16);
			break;

                case SD_BUS_TYPE_UINT16:
			dbg("push UINT16");
			lua_pushinteger(L, basic.u16);
                        break;

                case SD_BUS_TYPE_INT32:
                case SD_BUS_TYPE_UNIX_FD:
			dbg("push INT32/FD %i", basic.s32);
			lua_pushinteger(L, basic.s32);
			break;

                case SD_BUS_TYPE_UINT32:
			dbg("push UINT32");
			lua_pushinteger(L, basic.u32);
                        break;

                case SD_BUS_TYPE_INT64:
			dbg("push INT64");
			lua_pushinteger(L, basic.s64);
			break;

                case SD_BUS_TYPE_UINT64:
			dbg("push UINT64");
			lua_pushinteger(L, basic.u64);
                        break;

                case SD_BUS_TYPE_DOUBLE:
			dbg("push DOUBLE");
			lua_pushnumber(L, basic.d64);
                        break;

                case SD_BUS_TYPE_STRING:
                case SD_BUS_TYPE_OBJECT_PATH:
                case SD_BUS_TYPE_SIGNATURE:
			dbg("push STRING/OBJ/sig %s", basic.string);
			lua_pushstring(L, basic.string);
                        break;

                default:
                        luaL_error(L, "msg_tolua: unknown basic type: %c", type);
                }

	update_table:
		if (ctype == SD_BUS_TYPE_ARRAY || ctype == SD_BUS_TYPE_STRUCT) {

			if (lua_type(L, -2) != LUA_TTABLE)
				luaL_error(L, "%c rawseti: not table at -2", ctype);

			dbg("rawseti t[%lu]", lua_rawlen(L, -2) + 1);
			lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
		}
        }

        return 0;
}

int msg_tolua(lua_State *L, sd_bus_message* m)
{
	int ret, nargs = lua_gettop(L);
	ret = sd_bus_message_rewind(m, 1);
	if (ret < 0)
		luaL_error(L, "failed to rewind message");

	ret = __msg_tolua(L, m, 0);
	if (ret < 0)
		return ret;
	return lua_gettop(L) - nargs;
}
