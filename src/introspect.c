#include <stdio.h>
#include <systemd/sd-bus.h>
#include <assert.h>
#include <errno.h>

#include "lua.h"
#include "lauxlib.h"

#include <mxml.h>

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
static int load_dbus_xml_file(lua_State *L, const char* file)
{
	FILE *fp;
	mxml_node_t *root, *node, *intf, *prop, *met, *sig, *arg;

	fp = fopen(file, "r");

	if (fp == NULL)
		luaL_error(L, "failed to open %s", file);

	root = mxmlLoadFile(NULL, fp, MXML_OPAQUE_CALLBACK);
	fclose(fp);

	node = mxmlFindElement(root, root, "node", NULL, NULL, MXML_DESCEND);

	if (!node) {
		mxmlDelete(root);
		luaL_error(L, "failed to find <node> element");
	}

	for(intf = mxmlFindElement(node, node, "interface", NULL, NULL, MXML_DESCEND);
	    intf != NULL;
	    intf = mxmlFindElement(intf, node, "interface", NULL, NULL, MXML_NO_DESCEND)) {
		printf("interface: %s\n", mxmlElementGetAttr(intf, "name"));

		/* methods */
		for(met = mxmlFindElement(intf, intf, "method", NULL, NULL, MXML_DESCEND);
		    met != NULL;
		    met = mxmlFindElement(met, intf, "method", NULL, NULL, MXML_NO_DESCEND)) {
			printf("  method: %s\n", mxmlElementGetAttr(met, "name"));

			for(arg = mxmlFindElement(met, met, "arg", NULL, NULL, MXML_DESCEND);
			    arg != NULL;
			    arg = mxmlFindElement(arg, met, "arg", NULL, NULL, MXML_NO_DESCEND)) {
				printf("     arg: %s type=%s, dir=%s \n",
				       mxmlElementGetAttr(arg, "name"),
				       mxmlElementGetAttr(arg, "type"),
				       mxmlElementGetAttr(arg, "direction"));
			}
		}

		/* property */
		for(prop = mxmlFindElement(intf, intf, "property", NULL, NULL, MXML_DESCEND);
		    prop != NULL;
		    prop = mxmlFindElement(prop, intf, "property", NULL, NULL, MXML_NO_DESCEND)) {
			printf("  property: %s\n", mxmlElementGetAttr(prop, "name"));
		}

		/* signal */
		for(sig = mxmlFindElement(intf, intf, "signal", NULL, NULL, MXML_DESCEND);
		    sig != NULL;
		    sig = mxmlFindElement(sig, intf, "signal", NULL, NULL, MXML_NO_DESCEND)) {
			printf("  signal: %s\n", mxmlElementGetAttr(sig, "name"));
		}
	}

	mxmlDelete(root);
	return 0;
}

int lsdbus_xml_read(lua_State *L)
{
	const char* f = luaL_checkstring(L, 1);
	return load_dbus_xml_file(L, f);
}
