#ifndef __LSDBUS_H
#define __LSDBUS_H

#include <stdio.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>
#include <assert.h>
#include <errno.h>

#include "lua.h"
#include "lauxlib.h"

#if LUA_VERSION_NUM < 503
# include "compat-5.3.h"
#endif

#define DBUS_NAME_MAXLEN	255
#define LSDBUS_ERR_SEP		'|'

#define BUS_MT			"lsdbus.bus"
#define MSG_MT	 		"lsdbus.msg"
#define EVSRC_MT		"lsdbus.evsrc"
#define SLOT_MT			"lsdbus.slot"

#define VARIANT_MT		"lsdbus.variant"
#define ARRAY_MT		"lsdbus.array"
#define STRUCT_MT		"lsdbus.struct"

#define REG_SLOT_TABLE		"lsdbus.slot_table"
#define REG_EVSRC_TABLE		"lsdbus.evsrc_table"
#define REG_VTAB_USER_ARG	"lsdbus.vtab_user_arg"

#ifdef DEBUG
# define dbg(fmt, args...) ( fprintf(stderr, "%s:%u ", __FUNCTION__, __LINE__),	\
			     fprintf(stderr, fmt, ##args),	    \
			     fprintf(stderr, "\n") )
#else
# define dbg(fmt, args...)  do {} while (0)
#endif

#define LSDBUS_BUS_IS_DEFAULT	0x1

struct lsdbus_bus {
	sd_bus *b;
	uint32_t flags;
};

#define LSDBUS_SLOT_TYPE_MASK		0xf	/* 4 bits for slot type */

#define LSDBUS_SLOT_TYPE_VTAB		0x1
#define LSDBUS_SLOT_TYPE_MATCH		0x2
#define LSDBUS_SLOT_TYPE_ASYNC		0x3

struct lsdbus_slot {
	sd_bus_slot *slot;
	uint32_t flags;
	/* slot type specific data */
	union {
		struct sd_bus_vtable *vt;
	};
};

#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

sd_bus* lua_checksdbus(lua_State *L, int index);

int push_sd_bus_error(lua_State* L, const sd_bus_error* err);
int msg_fromlua(lua_State *L, sd_bus_message *m, const char *types, int stpos);
int msg_tolua(lua_State *L, sd_bus_message* m, int raw);

int evl_loop(lua_State *L);
int evl_run(lua_State *L);
int evl_exit(lua_State *L);
void evl_cleanup(sd_bus *bus);

int evl_add_signal(lua_State *L);
int evl_add_periodic(lua_State *L);
int evl_add_io(lua_State *L);
int evl_add_child(lua_State *L);
int evl_get_fd(lua_State *L);

extern const luaL_Reg lsdbus_evsrc_m [];
extern const luaL_Reg lsdbus_slot_m [];

int lsdbus_add_object_vtable(lua_State *L);
void vtable_cleanup(lua_State *L);
int lsdbus_emit_prop_changed(lua_State *L);
int lsdbus_emit_signal(lua_State *L);
int lsdbus_context(lua_State *L);
int lsdbus_credentials(lua_State *L);
int lsdbus_negotiate_credentials(lua_State *L);
struct lsdbus_slot* __lsdbus_slot_push(lua_State *L, sd_bus_slot *slot, uint32_t flags);
int lsdbus_slot_push(lua_State *L, sd_bus_slot *slot, uint32_t flags);
void init_reg_vtab_user(lua_State *L);

int lsdbus_xml_fromfile(lua_State *L);
int lsdbus_xml_fromstr(lua_State *L);

void regtab_store(lua_State *L, const char* regtab, void *k, int funidx);
int regtab_get(lua_State *L, const char* regtab, void *k);
void regtab_clear(lua_State *L, const char *regtab, void *k);

/* error parsing */
int errparse_init(void);
void errparse_cleanup(void);
const char* errparse(const char* errmsg, char* name);

const char* luaL_checkintf(lua_State *L, int arg);
const char* luaL_checkpath(lua_State *L, int arg);
const char* luaL_checkmember(lua_State *L, int arg);
const char *luaL_checkservice(lua_State *L, int arg);

#if LIBSYSTEMD_VERSION < 246
int sd_bus_interface_name_is_valid(const char *p);
int sd_bus_service_name_is_valid(const char *p);
int sd_bus_member_name_is_valid(const char* p);
int sd_bus_object_path_is_valid(const char* p);
#endif

#endif /* __LSDBUS_H */
