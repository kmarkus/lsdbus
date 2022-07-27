#ifndef __LSDBUS_H
#define __LSDBUS_H

#include <stdio.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>
#include <assert.h>
#include <errno.h>

#include "lua.h"
#include "lauxlib.h"

#if LUA_VERSION_NUM == 501
# include "lua5.1/compat-5.3.h"
#elif LUA_VERSION_NUM == 502
# include "lua5.2/compat-5.3.h"
#endif

#define DBUS_NAME_MAXLEN	255
#define LSDBUS_ERR_SEP		'|'

#define BUS_MT			"lsdbus.bus"
#define MSG_MT	 		"lsdbus.msg"
#define EVSRC_MT		"lsdbus.evsrc"
#define SLOT_MT			"lsdbus.slot"
#define GCSLOT_MT		"lsdbus.gcslot"

#define REG_SLOT_TABLE		"lsdbus.slot_table"
#define REG_EVSRC_TABLE		"lsdbus.evsrc_table"

#ifdef DEBUG
# define dbg(fmt, args...) ( fprintf(stderr, "%s: ", __FUNCTION__), \
			     fprintf(stderr, fmt, ##args),	    \
			     fprintf(stderr, "\n") )
#else
# define dbg(fmt, args...)  do {} while (0)
#endif

#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

int push_sd_bus_error(lua_State* L, const sd_bus_error* err);
int msg_fromlua(lua_State *L, sd_bus_message *m, const char *types, int stpos);
int msg_tolua(lua_State *L, sd_bus_message* m);

int evl_loop(lua_State *L);
int evl_run(lua_State *L);
int evl_exit(lua_State *L);
void evl_cleanup(sd_bus *bus);

int evl_add_signal(lua_State *L);
int evl_add_periodic(lua_State *L);
int evl_add_io(lua_State *L);

extern const luaL_Reg lsdbus_evsrc_m [];
extern const luaL_Reg lsdbus_slot_m [];
extern const luaL_Reg lsdbus_gcslot_m [];

int lsdbus_add_object_vtable(lua_State *L);
void vtable_cleanup(lua_State *L);
int lsdbus_emit_prop_changed(lua_State *L);
int lsdbus_emit_signal(lua_State *L);
int lsdbus_context(lua_State *L);
int lsdbus_slot_push(lua_State *L, sd_bus_slot *slot);
int lsdbus_gcslot_push(lua_State *L, sd_bus_slot *slot);

int lsdbus_xml_fromfile(lua_State *L);
int lsdbus_xml_fromstr(lua_State *L);

void regtab_store(lua_State *L, const char* regtab, void *k, int funidx);
int regtab_get(lua_State *L, const char* regtab, void *k);
void regtab_clear(lua_State *L, const char* regtab, void *k);

const char* luaL_checkintf(lua_State *L, int arg);
const char* luaL_checkpath(lua_State *L, int arg);
const char* luaL_checkmember(lua_State *L, int arg);
const char* luaL_checkservice(lua_State *L, int arg);

#endif /* __LSDBUS_H */
