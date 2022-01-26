#include <stdlib.h>
#include "lsdbus.h"

/*
 * parse error message, copy error name into name and return pointer
 * to message part in errmsg. Return NULL if parsing fails.
 */
static const char* parse_errmsg(const char* errmsg, char* name)
{
	const char *start, *sep;

	start = strstr(errmsg, ": ");
	if (!start) return NULL;

	sep = strchr(errmsg, LSDBUS_ERR_SEP);
	if (!sep) return NULL;

	strncpy(name, start+2, sep-start-2);

	return sep+1;
}

static int prop_get_handler(sd_bus *bus,
			    const char *path, const char *interface, const char *property,
			    sd_bus_message *reply, void *userdata, sd_bus_error *ret_error)
{
	int ret;
	const char *type;
	lua_State *L = (lua_State *) userdata;
	sd_bus_slot *slot = sd_bus_get_current_slot(bus);

	(void) path;
	(void) interface;

	dbg("%s, %s, %s, slot: %p", path, interface, property, slot);

	regtab_get(L, REG_SLOT_TABLE, slot);                    /* push slottab */
	lua_pushfstring(L, "p#%s", property);
	assert(lua_rawget(L, -2) == LUA_TTABLE);                /* push slottab[p#property] { type, get, set } */
	assert(lua_rawgeti(L, -1, 1) == LUA_TSTRING);           /* push [1] (type) */
	type = lua_tostring(L, -1);
	lua_pop(L, 1);

	assert(lua_rawgeti(L, -1, 2) == LUA_TFUNCTION);         /* push getter */

	ret = lua_pcall(L, 0, 1, 0);

	if (ret != LUA_OK) {
		char name[DBUS_NAME_MAXLEN] = {0};
		const char* errmsg = lua_tostring(L, -1);
		const char* message = parse_errmsg(errmsg, name);
		lua_settop(L, 1);

		if(message)
			return sd_bus_error_set(ret_error, name, message);
		else
			return sd_bus_error_set(ret_error, SD_BUS_ERROR_FAILED, errmsg);
	}

	ret = msg_fromlua(L, reply, type, -1);

	if(ret<0)
		lua_error(L);

	lua_settop(L, 1);

	return 1;
}

/**
 * Note: sd-bus is very picky about the state of the message after
 * calling the getter. Make sure only the value is read and nothing
 * more.
 */
static int prop_set_handler(sd_bus *bus,
			    const char *path, const char *interface, const char *property,
			    sd_bus_message *value, void *userdata, sd_bus_error *ret_error)
{
	int ret, nargs;
	lua_State *L = (lua_State *) userdata;
	sd_bus_slot *slot = sd_bus_get_current_slot(bus);
	(void) path, (void) interface;

	dbg("%s, %s, %s, slot: %p", path, interface, property, slot);

	regtab_get(L, REG_SLOT_TABLE, slot);                    /* push slottab */
	lua_pushfstring(L, "p#%s", property);
	assert(lua_rawget(L, -2) == LUA_TTABLE);                /* push slottab[p#property] { type, get, set } */

	assert(lua_rawgeti(L, -1, 3) == LUA_TFUNCTION);         /* push setter */

	nargs = msg_tolua(L, value);

	if(nargs<0)
		lua_error(L);

	ret = lua_pcall(L, nargs, 0, 0);

	if (ret != LUA_OK) {
		char name[DBUS_NAME_MAXLEN] = {0};
		const char* errmsg = lua_tostring(L, -1);
		const char* message = parse_errmsg(errmsg, name);
		lua_settop(L, 1);

		if(message)
			return sd_bus_error_set(ret_error, name, message);
		else
			return sd_bus_error_set(ret_error, SD_BUS_ERROR_FAILED, errmsg);
	}

	lua_settop(L, 1);

	return 1;
}

/**
 * lookup REG_VTAB[slot], push the handler onto the stack. if not
 * NULL, assign signature and result typestrings
 */
static void push_method(lua_State *L, sd_bus_slot *slot, const char* member, const char **result)
{
	int ret;
	dbg("getting slottab with slot %p", slot);

	regtab_get(L, REG_SLOT_TABLE, slot);                    /* push slottab */
	lua_pushfstring(L, "m#%s", member);
	assert(lua_rawget(L, -2) == LUA_TTABLE);                /* push slottab[m#member] { sig, res, handler } */
	ret = lua_rawgeti(L, -1, 2);                            /* push [2] (result typestr) */

	if (ret==LUA_TSTRING)
		*result = lua_tostring(L, -1);
	else
		*result = NULL;

	assert(lua_rawgeti(L, -2, 3) == LUA_TFUNCTION);         /* push handler */

	/* remove member and slottab, but keep the string on the stack
	 * since we're holding a ref to it */
	lua_remove(L, -3);
	lua_remove(L, -3);
}

static int method_handler(sd_bus_message *call, void *userdata, sd_bus_error *ret_error)
{
	int ret, nargs;
	sd_bus_message *reply = NULL;
	const char *result;

	lua_State *L = (lua_State *) userdata;
	sd_bus *b = sd_bus_message_get_bus(call);
	sd_bus_slot *slot = sd_bus_get_current_slot(b);
	const char *mem = sd_bus_message_get_member(call);

	push_method(L, slot, mem, &result);

	nargs = msg_tolua(L, call);

	if(nargs<0)
		lua_error(L);

	ret = lua_pcall(L, nargs, LUA_MULTRET, 0);

	if (ret != LUA_OK) {
		char name[DBUS_NAME_MAXLEN] = {0};
		const char* errmsg = lua_tostring(L, -1);
		const char* message = parse_errmsg(errmsg, name);
		lua_settop(L, 1);

		if(message)
			return sd_bus_error_set(ret_error, name, message);
		else
			return sd_bus_error_set(ret_error, SD_BUS_ERROR_FAILED, errmsg);
	}

        if (!sd_bus_message_get_expect_reply(call)) {
		dbg("no reply expected");
		goto out;
	}

        ret = sd_bus_message_new_method_return(call, &reply);

        if (ret < 0)
		luaL_error(L, "failed to create return message");

	if (result != NULL) {
		ret = msg_fromlua(L, reply, result, 3);

		if(ret<0)
			goto out_unref;
	}

        ret = sd_bus_send(b, reply, NULL);

	if(ret<0) {
		lua_pushfstring(L, "sd_bus_send failed: %s", strerror(-ret));
		goto out_unref;
	}

	/* all good */

out_unref:
	sd_bus_message_unrefp(&reply);
out:
	if (ret<0)
		lua_error(L);

	lua_settop(L, 1);
	return 1;
}

#ifdef DEBUG
static void vtable_dump(sd_bus_vtable *vt)
{
	for(sd_bus_vtable *i = vt;; i++) {
		if (i->type == _SD_BUS_VTABLE_END) {
			dbg("_SD_BUS_VTABLE_END");
			break;
		} else if (i->type == _SD_BUS_VTABLE_START) {
			dbg("_SD_BUS_VTABLE_START");
		} else if (i->type == _SD_BUS_VTABLE_METHOD) {
			dbg("method %s, sig: %s, res: %s, names: %p, handler: %p",
			    i->x.method.member,
			    i->x.method.signature, i->x.method.result,
			    i->x.method.names, i->x.method.handler);
		} else if (i->type == _SD_BUS_VTABLE_PROPERTY) {
			dbg("ro property %s, sig: %s, get: %p, set: %p",
			    i->x.property.member, i->x.property.signature,
			    i->x.property.get, i->x.property.set);
		} else if (i->type == _SD_BUS_VTABLE_WRITABLE_PROPERTY) {
			dbg("rw property %s, sig: %s, get: %p, set: %p",
			    i->x.property.member, i->x.property.signature,
			    i->x.property.get, i->x.property.set);
		} else if (i->type == _SD_BUS_VTABLE_SIGNAL) {
			dbg("signal %s, sig: %s, names: %p",
			    i->x.signal.member, i->x.signal.signature, i->x.signal.names);
		} else {
			dbg("unknown type");
		}
	}
}
#endif

static void vtable_free(sd_bus_vtable *vt)
{
	if (!vt)
		return;

	for (int i=1; vt[i].type != _SD_BUS_VTABLE_END; i++) {
		if (vt[i].type == _SD_BUS_VTABLE_METHOD) {
			free((char*)vt[i].x.method.member);
			free((char*)vt[i].x.method.signature);
			free((char*)vt[i].x.method.result);
			free((char*)vt[i].x.method.names);
		} else if (vt[i].type == _SD_BUS_VTABLE_SIGNAL) {
			free((char*)vt[i].x.signal.member);
			free((char*)vt[i].x.signal.signature);
			free((char*)vt[i].x.signal.names);
		} else if (vt[i].type == _SD_BUS_VTABLE_PROPERTY ||
			   vt[i].type == _SD_BUS_VTABLE_WRITABLE_PROPERTY) {
			free((char*)vt[i].x.property.member);
			free((char*)vt[i].x.property.signature);
		}
	}
	free(vt);
}

/* resize the given vtable to size i (excluding start and stop entries). */
static void vtable_resize(lua_State *L, sd_bus_vtable **vtp, int i)
{
	sd_bus_vtable *vt = realloc(*vtp, sizeof(struct sd_bus_vtable) * (i+2));

	if(!vt) {
		vtable_free(*vtp);
		luaL_error(L, "vtable allocation failed");
	}

	vt[0] = (sd_bus_vtable)	SD_BUS_VTABLE_START(0);
	vt[i+1] = (sd_bus_vtable) SD_BUS_VTABLE_END;
	*vtp = vt;
}

/* resize ptr but free it if it fails */
void* realloc2(char**ptr, size_t size)
{
	void *tmp = realloc(*ptr, size);
	if (tmp==NULL) {
		dbg("realloc2 failed");
		free(*ptr);
	}
	return tmp;
}

/* like lua_getfield, but expects the value to be a string whose value
 * is returned
 * WARNING: the returned string is only valid as long as
 * the string value stored in the table exists!
 */
const char* lua_getstrfield(lua_State *L, int index,
		      const char* field, size_t* len, const char* member)
{
	const char *res;

	int typ = lua_getfield(L, index, field);

	if (typ != LUA_TSTRING) {
		lua_pushfstring(L, "%s: field %s value not a string but %s",
				member, field, lua_typename(L, typ));
		return NULL;
	}

	res = lua_tolstring(L, -1, len);
	lua_pop(L, 1);
	return res;
}

static int vtable_add_signal(lua_State *L, sd_bus_vtable *vt, int slotref)
{
	int ret=-1, typ, sig_len=0, names_len=0;
	char *sig=NULL, *names=NULL, *member = NULL;

	size_t num_args = lua_rawlen(L, 6);

	member = strdup(lua_tostring(L, 5));

	for (unsigned int i=1; i<=num_args; i++) {
		const char *name, *type;
		size_t name_len, type_len;

		typ = lua_rawgeti(L, -1, i);
		if (typ != LUA_TTABLE) {
			lua_pushfstring(L, "signal %s: expected arg table but got %s",
					member, lua_typename(L, typ));
			goto out_free;
		}

		name = lua_getstrfield(L, -1, "name", &name_len, member);
		type = lua_getstrfield(L, -1, "type", &type_len, member);

		sig = realloc2(&sig, sig_len + type_len + 1);
		if (sig == NULL) goto alloc_failure;
		strcpy(sig + sig_len, type);
		sig_len += type_len;

		names = realloc2(&names, names_len + name_len + 1);
		if (names==NULL) goto alloc_failure;
		strcpy(names + names_len, name);
		names_len += name_len + 1; /* include '\0' */

		lua_pop(L, 1); /* argtab */
	}

	names = realloc2(&names, names_len+1);
	names[names_len] = '\0';

	*vt = (sd_bus_vtable) SD_BUS_SIGNAL_WITH_NAMES(member, sig, names, 0);

	/* populate slottab */
	lua_rawgeti(L, LUA_REGISTRYINDEX, slotref); /* slottab @ 7 */

	lua_pushfstring(L, "s#%s", member);	/* slottab key @8 */
	lua_pushstring(L, sig);			/* ptab @9 */

	lua_rawset(L, 7);                       /* slottab[p#member] = sig */
	lua_pop(L, 1);                          /* pop slottab */

	/* all ok */
	ret = 0;
	goto out;

alloc_failure:
	lua_pushfstring(L, "vtable allocation failed");
out_free:
	free(sig);
	free(names);
out:
	lua_settop(L, 6);
	return ret;
}

/**
 * populate a vtable entry from the property on the stack
 * expects property name at -2 and method arg table at -1
 * @return: 0 if OK, -1 otherwise and an error message at the top of the stack
 */
static int vtable_add_property(lua_State *L, sd_bus_vtable *vt, int slotref)
{
	int ret=-1, typ;
	const char* access, *type;

	sd_bus_property_get_t getter = NULL;
	sd_bus_property_set_t setter = NULL;

	const char *member = strdup(lua_tostring(L, 5));

	access = lua_getstrfield(L, 6,	"access", NULL, member);

	if(!strcmp(access, "read")) {
		getter = prop_get_handler;
	} else if (!strcmp(access, "write")) {
		setter = prop_set_handler;
	} else if (!strcmp(access, "readwrite")) {
		getter = prop_get_handler;
		setter = prop_set_handler;
	} else {
		lua_pushfstring(L, "%s: invalid access %s", member, access);
		goto out;
	}

	type = lua_getstrfield(L, 6, "type", NULL, member);

	lua_rawgeti(L, LUA_REGISTRYINDEX, slotref); /* slottab @ 7 */

	lua_pushfstring(L, "p#%s", member);	/* slottab key @8 */
	lua_newtable(L);			/* ptab @9 */

	lua_pushstring(L, type);
	lua_rawseti(L, -2, 1);                   /* ptab[1] = type */

	if(getter) {
		typ = lua_getfield(L, 6, "get");

		if (typ != LUA_TFUNCTION) {
			lua_pushfstring(L, "%s: invalid get, expected function, got %s",
					member,	lua_typename(L, typ));
			goto out;
		}

		lua_rawseti(L, -2, 2);                   /* ptab[2] = get */
	}

	if(setter) {
		typ = lua_getfield(L, 6, "set");

		if (typ != LUA_TFUNCTION) {
			lua_pushfstring(L, "%s: invalid set, expected function, got %s",
					member,	lua_typename(L, typ));
			goto out;
		}

		lua_rawseti(L, -2, 3);			/* ptab[3] = set */
	}

	dbg("adding property %s (%s)", member, access);

	if(!setter) {
		*vt = (sd_bus_vtable) SD_BUS_PROPERTY( member, strdup(type), getter, 0,
						       SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE);
	} else {
		*vt = (sd_bus_vtable) SD_BUS_WRITABLE_PROPERTY( member, strdup(type), getter, setter, 0,
								SD_BUS_VTABLE_UNPRIVILEGED |
								SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE);
	}

	/* populate slottab */
	lua_rawset(L, 7);                           /* slottab[p#member] = ptab */
	lua_pop(L, 1);                              /* pop slottab */

	/* all ok */
	ret = 0;

out:
	lua_settop(L, 6);
	return ret;
}

/**
 * populate a vtable entry from the method on the stack
 * expects method name at -2 and method arg table at -1
 * @return: 0 if OK, -1 otherwise and an error message at the top of the stack
 */
static int vtable_add_method(lua_State *L, sd_bus_vtable *vt, int slotref)
{
	int ret=-1, typ;
	char *sig=NULL, *res=NULL, *in_names=NULL, *out_names=NULL;
	size_t sig_len = 0, res_len = 0, in_names_len=0, out_names_len=0;

	const char *member = lua_tostring(L, 5);
	dbg("adding method %s", member);

	size_t num_args = lua_rawlen(L, 6);

	for (unsigned int i=1; i<=num_args; i++) {
		size_t name_len, type_len;
		const char *dir, *name, *type;

		/* push the the #i arg table on the stack { direction='in', name="foo", type="x" } */
		typ = lua_rawgeti(L, -1, i);
		if (typ != LUA_TTABLE) {
			lua_pushfstring(L, "method %s: expected table but got %s", member, lua_typename(L, typ));
			goto out_free;
		}

		/* direction */
		typ = lua_getfield(L, -1, "direction");
		if (typ != LUA_TSTRING) {
			lua_pushfstring(L, "method %s: arg direction not a string but %s", member, lua_typename(L, typ));
			goto out_free;
		}
		dir = lua_tostring(L, -1);

		/* argument name */
		typ = lua_getfield(L, -2, "name");
		if (typ != LUA_TSTRING) {
			lua_pushfstring(L, "method %s: arg name not a string but %s", member, lua_typename(L, typ));
			goto out_free;
		}
		name = lua_tolstring(L, -1, &name_len);

		/* type */
		typ = lua_getfield(L, -3, "type");
		if (typ != LUA_TSTRING) {
			lua_pushfstring(L, "method %s: arg type not a string but %s", member, lua_typename(L, typ));
			goto out_free;
		}
		type = lua_tolstring(L, -1, &type_len);

		/* construct in/out typestr and \0 separeted parameter names */
		if (strcmp(dir,	"in") == 0) {
			dbg("  added in arg %s (%s)", name, type);
			sig = realloc2(&sig, sig_len + type_len + 1);
			if (sig == NULL) goto alloc_failure;
			strcpy(sig + sig_len, type);
			sig_len += type_len;

			in_names = realloc2(&in_names, in_names_len + name_len + 1);
			if (in_names==NULL) goto alloc_failure;
			strcpy(in_names + in_names_len, name);
			in_names_len +=	name_len + 1; /* include '\0' */

		} else if (strcmp(dir,	"out") == 0) {
			dbg("  added out arg %s (%s)", name, type);
			res = realloc2(&res, res_len + type_len + 1);
			if (res==NULL) goto alloc_failure;
			strcpy(res + res_len, type);
			res_len += type_len;

			out_names = realloc2(&out_names, out_names_len + name_len + 1);
			if (out_names==NULL) goto alloc_failure;
			strcpy(out_names + out_names_len, name);
			out_names_len += name_len + 1; /* include '\0' */
		} else {
			lua_pushfstring(L, "method %s: invalid direction %s", member, dir);
			goto out_free;
		}

		/* pop type, name, direction and argtab */
		lua_pop(L, 4);
	}

	/* append out_names to in_names and free the former */
	dbg("  in_names_len: %zu, out_names_len: %zu", in_names_len, out_names_len);
	if (in_names_len + out_names_len) {
		in_names = realloc2(&in_names, in_names_len+out_names_len+1); /* +1 is for an extra \0 */
		if (in_names==NULL) goto alloc_failure;
		memcpy(in_names+in_names_len, out_names, out_names_len);
		in_names[in_names_len+out_names_len]='\0';
		free(out_names);
		out_names = NULL;
	}

	*vt = (sd_bus_vtable) SD_BUS_METHOD(
		strdup(member), sig, res, method_handler, SD_BUS_VTABLE_UNPRIVILEGED);

	vt->x.method.names = in_names;

	/* store information in slottab */
	lua_rawgeti(L, LUA_REGISTRYINDEX, slotref); /* slottab @ 7 */
	lua_pushfstring(L, "m#%s", member);         /* @ 8 */

	lua_newtable(L);                            /* mtab @ 9 */
	lua_pushstring(L, sig);                     /* sig @ 10  */
	lua_rawseti(L, -2, 1);                      /* mtab[1] = sig */

	lua_pushstring(L, res);
	lua_rawseti(L, -2, 2);                      /* mtab[2] = res */

	typ = lua_getfield(L, 6, "handler");

	if (typ != LUA_TFUNCTION) {
		dbg("method %s: invalid handler, expected function, got %s",
		    member,	lua_typename(L, typ));
		lua_pushfstring(L, "method %s: invalid handler, expected function, got %s",
				member,	lua_typename(L, typ));
		goto out; /* cleanup via vtable_free */
	}
	lua_rawseti(L, -2, 3);                      /* mtab[3] = handler */
	lua_rawset(L, 7);                           /* slottab[m#member] = mtab */
	lua_pop(L, 1);                              /* pop slottab */

	ret = 0;
	goto out;

alloc_failure:
	lua_pushfstring(L, "vtable allocation failed");
out_free:
	free(sig);
	free(res);
	free(in_names);
	free(out_names);
out:
	return ret;
}

/* create and populate a vtable from the equivalent Lua table at the
 * index idx of the stack. */
int lsdbus_add_object_vtable(lua_State *L)
{
	int ret, slotref;
	sd_bus_slot *slot;
	const char *interface, *path;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	path = luaL_checkstring (L, 2);
	luaL_checktype (L, 3, LUA_TTABLE);

	/* initialize vtable */
	size_t vt_len = 0;
	struct sd_bus_vtable *vt = NULL;
	vtable_resize(L, &vt, vt_len);

	/* eventually the data belonging to this vtable will be stored
	 * in the REG_SLOT_TABLE. Until we get a slot ptr, we store it
	 * under the a ref in the registry */

	lua_newtable(L);
	slotref = luaL_ref(L, LUA_REGISTRYINDEX);

	/* methods */
	ret = lua_getfield(L, 3, "methods");

	if (ret == LUA_TNIL) {
		goto do_props;
	} else if (ret != LUA_TTABLE) {
		lua_pushfstring(L, "methods: expected table but got %s", lua_typename(L, ret));
		goto fail;
	}

	lua_pushnil(L);
	while (lua_next(L, 4) != 0) {

		if(lua_type(L, -1) != LUA_TTABLE) {
			lua_pushfstring(L, "method %s: expected table but got %s",
					lua_tostring(L, -2), lua_typename(L, ret));
			goto fail;
		}

		vtable_resize(L, &vt, ++vt_len);
		if (vtable_add_method(L, &vt[vt_len], slotref) != 0)
			goto fail;
		lua_pop(L, 1); /* pop method table */
	}

do_props:
	lua_pop(L, 1); /* pop methods table */

	/* properties */
	ret = lua_getfield(L, 3, "properties");

	if (ret == LUA_TNIL) {
		goto do_sigs;
	} else if (ret != LUA_TTABLE) {
		lua_pushfstring(L, "properties: expected table but got %s", lua_typename(L, ret));
		goto fail;
	}

	lua_pushnil(L);
	while (lua_next(L, 4) != 0) {

		if(lua_type(L, -1) != LUA_TTABLE) {
			lua_pushfstring(L, "properties %s: expected table but got %s",
					lua_tostring(L, -2), lua_typename(L, ret));
			goto fail;
		}

		vtable_resize(L, &vt, ++vt_len);
		if (vtable_add_property(L, &vt[vt_len], slotref) != 0)
			goto fail;
		lua_pop(L, 1); /* pop property table */
	}

do_sigs:
	lua_pop(L, 1); /* pop properties table */
	dbg("top: %i", lua_gettop(L));

	/* signals */
	ret = lua_getfield(L, 3, "signals");

	if (ret == LUA_TNIL) {
		goto reg_vtab;
	} else if (ret != LUA_TTABLE) {
		lua_pushfstring(L, "signals: expected table but got %s", lua_typename(L, ret));
		goto fail;
	}

	lua_pushnil(L);
	while (lua_next(L, 4) != 0) {

		if(lua_type(L, -1) != LUA_TTABLE) {
			lua_pushfstring(L, "signals %s: expected table but got %s",
					lua_tostring(L, -2), lua_typename(L, ret));
			goto fail;
		}

		vtable_resize(L, &vt, ++vt_len);
		if (vtable_add_signal(L, &vt[vt_len], slotref) != 0)
			goto fail;
		lua_pop(L, 1); /* pop signal table */
	}


reg_vtab:
	lua_pop(L, 1); /* signals table */

	/* interface name */
	ret = lua_getfield(L, 3, "name");

	if (ret != LUA_TSTRING) {
		lua_pushfstring(L, "name: expected (interface) string but got %s", lua_typename(L, ret));
		goto fail;
	}

	interface = lua_tostring(L, -1);

#ifdef DEBUG
	dbg("adding obj vtab: path: %s, intf: %s", path, interface);
	dbg("*** vtable_dump ***");
	vtable_dump(vt);
	dbg("*** vtable_dump end*** ");
#endif

	ret = sd_bus_add_object_vtable(b, &slot, path, interface, vt, L);

	if (ret < 0) {
		lua_pushfstring(L, "failed to add vtable: %s", strerror(-ret));
		goto fail;
	}

	lua_pop(L, 1); /* interface */

	/* move the slottab from the registry to REG_SLOT_TABLE[slot] */
	lua_rawgeti(L, LUA_REGISTRYINDEX, slotref);
	lua_pushlightuserdata(L, vt);
	lua_setfield(L, -2, "vtable");

	regtab_store(L, REG_SLOT_TABLE, slot, -1);
	luaL_unref(L, LUA_REGISTRYINDEX, slotref);

	return 0;

fail:
	vtable_free(vt);
	return lua_error(L);
}

int lsdbus_emit_prop_changed(lua_State *L)
{
	int ret;
	int nprops = lua_gettop(L) - 3;
	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	const char *path = luaL_checkstring (L, 2);
	const char *intf = luaL_checkstring (L, 3);
	const char* props[nprops+1];

	for (int i=0; i<nprops; i++)
		props[i] = luaL_checkstring (L, i+4);

	props[nprops] = NULL;

	ret = sd_bus_emit_properties_changed_strv(b, path, intf, (char**) props);

	if (ret < 0)
		luaL_error(L, "emit_properties_changed failed: %s", strerror(-ret));

	return 0;
}

int lsdbus_emit_signal(lua_State *L)
{
	int ret;

	sd_bus_message *message = NULL;
	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	const char *path = luaL_checkstring (L, 2);
	const char *intf = luaL_checkstring (L, 3);
	const char *member = luaL_checkstring (L, 4);
	const char *sig = luaL_optstring (L, 5, NULL);

	ret = sd_bus_message_new_signal(b, &message, path, intf, member);
	if (ret < 0)
		goto out;

	if (sig) {
		ret = msg_fromlua(L, message, sig, 6);

		if (ret < 0)
			goto out;
	}

	ret = sd_bus_send(b, message, NULL);

out:
	sd_bus_message_unref(message);

	if (ret < 0)
		luaL_error(L, "emit_properties_changed failed: %s", strerror(-ret));

	return 0;
}

int lsdbus_context(lua_State *L)
{
	const char *dest, *path, *intf, *member, *sender;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	sd_bus_message* m = sd_bus_get_current_message(b);

	intf = sd_bus_message_get_interface(m);
	path = sd_bus_message_get_path(m);
	member = sd_bus_message_get_member(m);
	sender = sd_bus_message_get_sender(m);
	dest = sd_bus_message_get_destination(m);

	lua_newtable(L);

	lua_pushstring(L, intf);
	lua_setfield(L, -2, "interface");

	lua_pushstring(L, path);
	lua_setfield(L, -2, "path");

	lua_pushstring(L, member);
	lua_setfield(L, -2, "member");

	lua_pushstring(L, sender);
	lua_setfield(L, -2, "sender");

	lua_pushstring(L, dest);
	lua_setfield(L, -2, "destination");

	return 1;
}

void vtable_cleanup(lua_State *L)
{
	sd_bus_vtable *vtab;

	if (lua_getfield(L, LUA_REGISTRYINDEX, REG_SLOT_TABLE) != LUA_TTABLE)
		return;

	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		if (lua_type(L, -1) != LUA_TTABLE)
			goto next;

		if(lua_getfield(L, -1, "vtable") != LUA_TLIGHTUSERDATA)
			goto pop_vtable;

		vtab = lua_touserdata(L, -1);
		vtable_free(vtab);

	pop_vtable:
		lua_pop(L, 1);
	next:
		lua_pop(L, 1);
	}

	/* clear REG_SLOT_TABLE */
	lua_pushnil(L);
	lua_setfield(L, LUA_REGISTRYINDEX, REG_SLOT_TABLE);
}
