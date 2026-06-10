#include <stdio.h>
#include <systemd/sd-bus.h>
#include <assert.h>
#include <errno.h>

#include "lsdbus.h"


#include <mxml.h>

#ifdef HAVE_MXML4
#define MXML_DESCEND	MXML_DESCEND_ALL
#define MXML_NO_DESCEND	MXML_DESCEND_NONE

static mxml_node_t *mxml_load_file_opaque(FILE *fp)
{
	mxml_options_t *opts = mxmlOptionsNew();
	mxml_node_t *root;
	mxmlOptionsSetTypeValue(opts, MXML_TYPE_OPAQUE);
	root = mxmlLoadFile(NULL, opts, fp);
	mxmlOptionsDelete(opts);
	return root;
}

static mxml_node_t *mxml_load_string_opaque(const char *s)
{
	mxml_options_t *opts = mxmlOptionsNew();
	mxml_node_t *root;
	mxmlOptionsSetTypeValue(opts, MXML_TYPE_OPAQUE);
	root = mxmlLoadString(NULL, opts, s);
	mxmlOptionsDelete(opts);
	return root;
}
#else
#define mxml_load_file_opaque(fp)    mxmlLoadFile(NULL, (fp), MXML_OPAQUE_CALLBACK)
#define mxml_load_string_opaque(s)   mxmlLoadString(NULL, (s), MXML_OPAQUE_CALLBACK)
#endif


/*
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node name="/com/example/sample_object0">
  <interface name="com.example.SampleInterface0">
    <method name="Frobate">
      <arg name="foo" type="i" direction="in"/>
      <arg name="bar" type="s" direction="out"/>
      <arg name="baz" type="a{us}" direction="out"/>
      <annotation name="org.freedesktop.DBus.Deprecated" value="true"/>
    </method>
    <method name="Bazify">
      <arg name="bar" type="(iiu)" direction="in"/>
      <arg name="bar" type="v" direction="out"/>
    </method>
    <method name="Mogrify">
      <arg name="bar" type="(iiav)" direction="in"/>
    </method>
    <signal name="Changed">
      <arg name="new_value" type="b"/>
    </signal>
    <property name="Bar" type="y" access="readwrite"/>
  </interface>
  <node name="child_of_sample_object"/>
  <node name="another_child_of_sample_object"/>
</node>
*/

/*
 * convert the given D-Bus XML node to it's corresponding Lua
 * representation.
 */
static int dbus_xml2lua(lua_State *L, mxml_node_t *root)
{
	mxml_node_t *node, *subnode, *intf, *prop, *met, *sig, *arg;

	/* mxml returns <node> as root when parsing plain XML (no DOCTYPE wrapper) */
	const char *root_tag = mxmlGetElement(root);
	if (root_tag && strcmp(root_tag, "node") == 0) {
		node = root;
	} else {
		node = mxmlFindElement(root, root, "node", NULL, NULL, MXML_DESCEND);
	}

	if (!node) {
		mxmlDelete(root);
		luaL_error(L, "failed to find <node> element");
	}

	lua_newtable(L); /* result */

	const char *node_name = mxmlElementGetAttr(node, "name");
	if (node_name) {
		lua_pushstring(L, "name");
		lua_pushstring(L, node_name);
		lua_rawset(L, -3);
	}

	lua_pushstring(L, "interfaces");
	lua_newtable(L); /* interfaces */

	for(intf = mxmlFindElement(node, node, "interface", NULL, NULL, MXML_DESCEND);
	    intf != NULL;
	    intf = mxmlFindElement(intf, node, "interface", NULL, NULL, MXML_NO_DESCEND)) {

		/* skip malformed elements without mandatory name
		 * attribute (here and below). pushing the NULL
		 * returned by mxmlElementGetAttr would push nil,
		 * making the subsequent rawset raise (and leak the
		 * mxml tree) */
		if (mxmlElementGetAttr(intf, "name") == NULL)
			continue;

		/* interface */
		lua_newtable(L);

		lua_pushstring(L, "name");
		lua_pushstring(L, mxmlElementGetAttr(intf, "name"));
		lua_rawset(L, -3);

		/* methods */
		lua_pushstring(L, "methods");
		lua_newtable(L);

		for(met = mxmlFindElement(intf, intf, "method", NULL, NULL, MXML_DESCEND);
		    met != NULL;
		    met = mxmlFindElement(met, intf, "method", NULL, NULL, MXML_NO_DESCEND)) {
			if (mxmlElementGetAttr(met, "name") == NULL)
				continue;
			/* method */
			lua_pushstring(L, mxmlElementGetAttr(met, "name"));
			lua_newtable(L);

			for(arg = mxmlFindElement(met, met, "arg", NULL, NULL, MXML_DESCEND);
			    arg != NULL;
			    arg = mxmlFindElement(arg, met, "arg", NULL, NULL, MXML_NO_DESCEND)) {
				lua_newtable(L); /* arg */

				lua_pushstring(L, "name");
				lua_pushstring(L, mxmlElementGetAttr(arg, "name"));
				lua_rawset(L, -3);

				lua_pushstring(L, "type");
				lua_pushstring(L, mxmlElementGetAttr(arg, "type"));
				lua_rawset(L, -3);

				lua_pushstring(L, "direction");
				lua_pushstring(L, mxmlElementGetAttr(arg, "direction"));
				lua_rawset(L, -3);

				/* method[#method+1] = arg */
				lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
			}

			lua_rawset(L, -3); /* methods[name] = method */
		}
		lua_rawset(L, -3); /* interface.methods = methods */

		/* properties */
		lua_pushstring(L, "properties");
		lua_newtable(L);

		for(prop = mxmlFindElement(intf, intf, "property", NULL, NULL, MXML_DESCEND);
		    prop != NULL;
		    prop = mxmlFindElement(prop, intf, "property", NULL, NULL, MXML_NO_DESCEND)) {
			if (mxmlElementGetAttr(prop, "name") == NULL)
				continue;
			lua_pushstring(L, mxmlElementGetAttr(prop, "name"));
			lua_newtable(L);

			lua_pushstring(L, "type");
			lua_pushstring(L, mxmlElementGetAttr(prop, "type"));
			lua_rawset(L, -3);

			lua_pushstring(L, "access");
			lua_pushstring(L, mxmlElementGetAttr(prop, "access"));
			lua_rawset(L, -3);

			lua_rawset(L, -3); /* properties[name] = property */
		}

		lua_rawset(L, -3); /* interface.properties = properties */

		/* signal */
		lua_pushstring(L, "signals");
		lua_newtable(L);

		for(sig = mxmlFindElement(intf, intf, "signal", NULL, NULL, MXML_DESCEND);
		    sig != NULL;
		    sig = mxmlFindElement(sig, intf, "signal", NULL, NULL, MXML_NO_DESCEND)) {
			if (mxmlElementGetAttr(sig, "name") == NULL)
				continue;
			lua_pushstring(L,  mxmlElementGetAttr(sig, "name"));
			lua_newtable(L);

			for(arg = mxmlFindElement(sig, sig, "arg", NULL, NULL, MXML_DESCEND);
			    arg != NULL;
			    arg = mxmlFindElement(arg, sig, "arg", NULL, NULL, MXML_NO_DESCEND)) {
				lua_newtable(L); /* arg */

				lua_pushstring(L, "name");
				lua_pushstring(L, mxmlElementGetAttr(arg, "name"));
				lua_rawset(L, -3);

				lua_pushstring(L, "type");
				lua_pushstring(L, mxmlElementGetAttr(arg, "type"));
				lua_rawset(L, -3);

				/* signal[#signal+1] = arg */
				lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
			}
			lua_rawset(L, -3); /* signals[name] = signal */
		}

		lua_rawset(L, -3); /* interface.signals = signals */

		/* interfaces[#interfaces+1] = interface */
		lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
	}
	lua_rawset(L, -3); /* result.interfaces = interfaces */

	/* subnodes */
	lua_pushstring(L, "nodes");
	lua_newtable(L);

	for(subnode = mxmlFindElement(node, node, "node", NULL, NULL, MXML_DESCEND);
	    subnode != NULL;
	    subnode = mxmlFindElement(subnode, node, "node", NULL, NULL, MXML_NO_DESCEND)) {
		if (mxmlElementGetAttr(subnode, "name") == NULL)
			continue;
		dbg("%s", mxmlElementGetAttr(subnode, "name"));
		lua_pushstring(L, mxmlElementGetAttr(subnode, "name"));
		lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
	}

	lua_rawset(L, -3); /* result.nodes = nodes */

	mxmlDelete(root);
	return 0;
}

int lsdbus_xml_fromfile(lua_State *L)
{

	FILE *fp;
	mxml_node_t *root;

	const char* f = luaL_checkstring(L, 1);

	fp = fopen(f, "r");

	if (fp == NULL)
		luaL_error(L, "failed to open %s", f);

	root = mxml_load_file_opaque(fp);

	fclose(fp);

	if (root == NULL)
		luaL_error(L, "failed to parse file %s", f);

	dbus_xml2lua(L, root);
	return 1;
}

static char* skip_ws(const char* s) {
    while (*s && (*s == ' ' || *s == '\t' || *s == '\n')) s++;
    return (char*)s;
}

int lsdbus_xml_fromstr(lua_State *L)
{
	mxml_node_t *root;
	const char* s = luaL_checkstring(L, 1);

	root = mxml_load_string_opaque(skip_ws(s));

	if (root == NULL)
		luaL_error(L, "failed to parse XML string");

	dbus_xml2lua(L, root);
	return 1;
}
