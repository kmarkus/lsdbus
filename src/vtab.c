#include <stdlib.h>
#include "lsdbus.h"

#define SDBUS_VTAB	"sd_bus_vtable"
#define USER_VTAB	"user_vtable"

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

	regtab_get(L, REG_SLOT_TABLE, slot);                    /* slottab */
	lua_pushfstring(L, "p#%s", property);
	assert(lua_rawget(L, -2) == LUA_TTABLE);                /* slottab, {type,get,set} */

	assert(lua_rawgeti(L, -1, 1) == LUA_TSTRING);           /* slottab, {type,get,set}, type */
	type = lua_tostring(L, -1);
	lua_pop(L, 1);						/* slottab, {type,get,set} */

	assert(lua_rawgeti(L, -1, 2) == LUA_TFUNCTION);         /* slottab, {type,get,set}, get */

	lua_pushstring(L, USER_VTAB);				/* slottab, {type,get,set}, get, "user-vt" */
	lua_rawget(L, -4);					/* slottab, {type,get,set}, get, {} */

	ret = lua_pcall(L, 1, 1, 0);

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

	regtab_get(L, REG_SLOT_TABLE, slot);                    /* slottab */
	lua_pushfstring(L, "p#%s", property);
	assert(lua_rawget(L, -2) == LUA_TTABLE);                /* slottab, {type,get,set} */
	assert(lua_rawgeti(L, -1, 3) == LUA_TFUNCTION);         /* slottab, {type,get,set}, setter */
	lua_pushstring(L, USER_VTAB);				/* slottab, {type,get,set}, handler, "user-vt" */
	lua_rawget(L, -4);					/* slottab, {type,get,set}, handler, {} */

	nargs = msg_tolua(L, value);

	if(nargs<0)
		lua_error(L);

	ret = lua_pcall(L, 1+nargs, 0, 0);

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
 * lookup the REG_VTAB[slot] table t, push the the handler t[3] and
 * the user_vtable onto the stack. Assign the signature typestring
 * t[1] if it non-nil.
 */
static void push_method(lua_State *L, sd_bus_slot *slot, const char* member, const char **result)
{
	int ret;
	dbg("getting slottab with slot %p", slot);

	regtab_get(L, REG_SLOT_TABLE, slot);                    /* slottab */
	lua_pushfstring(L, "m#%s", member);			/* slottab, "m#member" */
	assert(lua_rawget(L, -2) == LUA_TTABLE);                /* slottab, {sig,res,hdlr} */
	ret = lua_rawgeti(L, -1, 2);                            /* slottab, {sig,res,hdlr}, res-typestr */

	if (ret==LUA_TSTRING)
		*result = lua_tostring(L, -1);
	else
		*result = NULL;

	lua_pop(L, 1);						/* slottab, {sig,res,hdrl} */

	assert(lua_rawgeti(L, -1, 3) == LUA_TFUNCTION);         /* slottab, {sig,res,hdlr}, handler */
	lua_pushstring(L, USER_VTAB);				/* slottab, {sig,res,hdlr}, handler, "user-vt" */
	lua_rawget(L, -4);					/* slottab, {sig,res,hdlr}, handler, {} */

	/* remove slottab and memtab */
	lua_remove(L, -3);
	lua_remove(L, -3);					/* handler, {} */
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

	ret = lua_pcall(L, 1+nargs, LUA_MULTRET, 0);

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
		ret = msg_fromlua(L, reply, result, 2);

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

/* like lua_getfield, but expects the value to be a string of which a
 * copy is returned. The memory must be freed by the caller. In case
 * of error NULL is returned and an error is pushed on the stack.
 */
char* lua_getstrfield(lua_State *L, int index,
		      const char* field, size_t* len, const char* member)
{
	size_t l;
	char *res;
	const char *tmp;

	int typ = lua_getfield(L, index, field);

	if (typ != LUA_TSTRING) {
		lua_pushfstring(L, "%s: field %s value not a string but %s",
				member, field, lua_typename(L, typ));
		return NULL;
	}

	tmp = lua_tolstring(L, -1, &l);
	lua_pop(L, 1);

	dbg("%s: l: %u, s: %s", __func__, l, tmp);

	res = calloc(1, l+1);

	if (res == NULL) {
		lua_pushfstring(L, "%s: failed to alloc memory for field %s value", member, field);
		return NULL;
	}

	dbg("res: %p", res);
	memcpy(res, tmp, l);
	if (len != NULL)
		*len = l;

	dbg("%s: s: %s", __func__, res);
	return res;
}

static int vtable_add_signal(lua_State *L, sd_bus_vtable *vt, int slotref)
{
	char *sig=NULL, *names=NULL, *member = NULL;

	if ((member = strdup(lua_tostring(L, 5))) == NULL) {
		lua_pushfstring(L, "failed to allocate memory for signal member");
		goto fail;
	}

	dbg("adding signal %s", member);

	if ((sig = lua_getstrfield(L, 6, "sig", NULL, member)) == NULL)
		goto fail;

	if ((names = lua_getstrfield(L, 6, "names", NULL, member)) == NULL)
		goto fail;

	*vt = (sd_bus_vtable) SD_BUS_SIGNAL_WITH_NAMES(member, sig, names, 0);

	/* populate slottab */
	lua_rawgeti(L, LUA_REGISTRYINDEX, slotref); /* slottab @ 7 */

	lua_pushfstring(L, "s#%s", member);	/* slottab key @8 */
	lua_pushstring(L, sig);			/* ptab @9 */

	lua_rawset(L, 7);                       /* slottab[p#member] = sig */
	lua_pop(L, 1);                          /* pop slottab */

	/* all ok */
	lua_settop(L, 6);
	return 0;

fail:
	free(member);
	free(sig);
	free(names);
	return -1;
}

/**
 * populate a vtable entry from the property on the stack
 * expects property name at -2 and method arg table at -1
 * @return: 0 if OK, -1 otherwise and an error message at the top of the stack
 */
static int vtable_add_property(lua_State *L, sd_bus_vtable *vt, int slotref)
{
	int typ;
	char *type, *member;
	const char *access;

	sd_bus_property_get_t getter = NULL;
	sd_bus_property_set_t setter = NULL;

	if ((member = strdup(lua_tostring(L, 5))) == NULL) {
		lua_pushfstring(L, "failed to allocate memory for property member");
		goto fail;
	}

	if ((typ = lua_getfield(L, 6, "access")) != LUA_TSTRING) {
		lua_pushfstring(L, "%s: invalid access, expected string, got %s",
				member,	lua_typename(L, typ));
		goto fail;
	}
	access = lua_tostring(L, -1);
	lua_pop(L, 1);

	if(!strcmp(access, "read")) {
		getter = prop_get_handler;
	} else if (!strcmp(access, "write")) {
		setter = prop_set_handler;
	} else if (!strcmp(access, "readwrite")) {
		getter = prop_get_handler;
		setter = prop_set_handler;
	} else {
		lua_pushfstring(L, "%s: invalid access %s", member, access);
		goto fail;
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
			goto fail;
		}

		lua_rawseti(L, -2, 2);                   /* ptab[2] = get */
	}

	if(setter) {
		typ = lua_getfield(L, 6, "set");

		if (typ != LUA_TFUNCTION) {
			lua_pushfstring(L, "%s: invalid set, expected function, got %s",
					member,	lua_typename(L, typ));
			goto fail;
		}

		lua_rawseti(L, -2, 3);			/* ptab[3] = set */
	}

	dbg("adding property %s (%s)", member, access);

	if(!setter) {
		*vt = (sd_bus_vtable) SD_BUS_PROPERTY( member, type, getter, 0,
						       SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE);
	} else {
		*vt = (sd_bus_vtable) SD_BUS_WRITABLE_PROPERTY( member, type, getter, setter, 0,
								SD_BUS_VTABLE_UNPRIVILEGED |
								SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE);
	}

	/* populate slottab */
	lua_rawset(L, 7);                           /* slottab[p#member] = ptab */
	lua_pop(L, 1);                              /* pop slottab */

	/* all ok */
	lua_settop(L, 6);
	return 0;
fail:
	free(member);
	free(type);
	return -1;
}

/**
 * populate a vtable entry from the method on the stack
 * expects method name at -2 and method arg table at -1
 * @return: 0 if OK, -1 otherwise and an error message at the top of the stack
 */
static int vtable_add_method(lua_State *L, sd_bus_vtable *vt, int slotref)
{
	int typ;
	char *member=NULL, *sig=NULL, *res=NULL, *names=NULL;

	if ((member = strdup(lua_tostring(L, 5))) == NULL) {
		lua_pushfstring(L, "failed to allocate memory for method member");
		goto fail;
	}

	dbg("adding method %s", member);

	if ((sig = lua_getstrfield(L, 6, "sig", NULL, member)) == NULL)
		goto fail;

	if ((res = lua_getstrfield(L, 6, "res", NULL, member)) == NULL)
		goto fail;

	if ((names = lua_getstrfield(L, 6, "names", NULL, member)) == NULL)
		goto fail;

	*vt = (sd_bus_vtable) SD_BUS_METHOD(member, sig, res, method_handler, SD_BUS_VTABLE_UNPRIVILEGED);
	vt->x.method.names = names;

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
		    member, lua_typename(L, typ));
		lua_pushfstring(L, "method %s: invalid handler, expected function, got %s",
				member, lua_typename(L, typ));
		goto fail;
	}
	lua_rawseti(L, -2, 3);                      /* mtab[3] = handler */
	lua_rawset(L, 7);                           /* slottab[m#member] = mtab */
	lua_pop(L, 1);                              /* pop slottab */

	return 0;

fail:
	free(member);
	free(names);
	free(sig);
	free(res);
	return -1;
}

/* create and populate a vtable from the equivalent Lua table at the
 * index idx of the stack. */
int lsdbus_add_object_vtable(lua_State *L)
{
	int ret, slotref;
	sd_bus_slot *slot;
	const char *interface, *path;

	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	path = luaL_checkpath (L, 2);
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

	/* save sd_bus_vtable (for gc) */
	lua_pushlightuserdata(L, vt);
	lua_setfield(L, -2, SDBUS_VTAB);

	/* save user vtable (for passing in ops) */
	lua_pushvalue(L, 3);
	lua_setfield(L, -2, USER_VTAB);

	regtab_store(L, REG_SLOT_TABLE, slot, -1);
	luaL_unref(L, LUA_REGISTRYINDEX, slotref);

	sd_bus_slot_set_description(slot, "vtab");
	return lsdbus_slot_push(L, slot);

fail:
	vtable_free(vt);
	return lua_error(L);
}

int lsdbus_emit_prop_changed(lua_State *L)
{
	int ret;
	int nprops = lua_gettop(L) - 3;
	sd_bus *b = *((sd_bus**) luaL_checkudata(L, 1, BUS_MT));
	const char *path = luaL_checkpath(L, 2);
	const char *intf = luaL_checkintf(L, 3);
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
	const char *path = luaL_checkpath (L, 2);
	const char *intf = luaL_checkintf (L, 3);
	const char *member = luaL_checkmember (L, 4);
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
		luaL_error(L, "emit_signal failed: %s", strerror(-ret));

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

		if(lua_getfield(L, -1, SDBUS_VTAB) != LUA_TLIGHTUSERDATA)
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

int lsdbus_slot_push(lua_State *L, sd_bus_slot *slot)
{
	sd_bus_slot **slotp = (sd_bus_slot**) lua_newuserdata(L, sizeof(sd_bus_slot*));
	*slotp = slot;
	luaL_getmetatable(L, SLOT_MT);
	lua_setmetatable(L, -2);
	return 1;
}

int lsdbus_slot_gc(lua_State *L)
{
	sd_bus_slot *slot = *((sd_bus_slot**) luaL_checkudata(L, 1, SLOT_MT));
	regtab_clear(L,	REG_SLOT_TABLE, slot);
	sd_bus_slot_unref(slot);
	return 0;
}

int lsdbus_slot_unref(lua_State *L)
{
	lsdbus_slot_gc(L);
	/* invalidate slot userdata */
	lua_pushnil(L);
	lua_setmetatable(L, -2);
	return 0;
}

int lsdbus_slot_tostring(lua_State *L)
{
	const char *desc = NULL;
	sd_bus_slot *slot = *((sd_bus_slot**) luaL_checkudata(L, 1, SLOT_MT));
	sd_bus_slot_get_description(slot, &desc);
	lua_pushfstring(L, "slot [%s] %p", (desc!=NULL)?desc:"unknown", slot);
	return 1;
}


const luaL_Reg lsdbus_slot_m [] = {
	{ "unref", lsdbus_slot_unref },
	{ "__tostring", lsdbus_slot_tostring },
	{ NULL, NULL }
};


int lsdbus_gcslot_gc(lua_State *L)
{
	sd_bus_slot *slot = *((sd_bus_slot**) luaL_checkudata(L, 1, GCSLOT_MT));
	regtab_clear(L,	REG_SLOT_TABLE, slot);
	sd_bus_slot_unref(slot);
	return 0;
}

int lsdbus_gcslot_push(lua_State *L, sd_bus_slot *slot)
{
	sd_bus_slot **slotp = (sd_bus_slot**) lua_newuserdata(L, sizeof(sd_bus_slot*));
	*slotp = slot;
	luaL_getmetatable(L, GCSLOT_MT);
	lua_setmetatable(L, -2);
	return 1;
}

int lsdbus_gcslot_unref(lua_State *L)
{
	lsdbus_gcslot_gc(L);
	/* invalidate slot userdata */
	lua_pushnil(L);
	lua_setmetatable(L, -2);
	return 0;
}

int lsdbus_gcslot_tostring(lua_State *L)
{
	const char *desc = NULL;
	sd_bus_slot *slot = *((sd_bus_slot**) luaL_checkudata(L, 1, GCSLOT_MT));
	sd_bus_slot_get_description(slot, &desc);
	lua_pushfstring(L, "slot [%s] %p", (desc!=NULL)?desc:"unknown", slot);
	return 1;
}

const luaL_Reg lsdbus_gcslot_m [] = {
	{ "unref", lsdbus_gcslot_unref },
	{ "__tostring", lsdbus_gcslot_tostring },
	{ "__gc", lsdbus_gcslot_gc },
	{ NULL, NULL }
};
