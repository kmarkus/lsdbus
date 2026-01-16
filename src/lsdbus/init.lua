
if _VERSION < "Lua 5.3" then
   require("compat53")
end

local lsdbus = require "lsdbus.core"
local common = require("lsdbus.common")

lsdbus.proxy = require("lsdbus.proxy")
lsdbus.server = require("lsdbus.server")
lsdbus.error = require("lsdbus.error")

local lom = require("lxp.lom")

lsdbus.PropIntf = 'org.freedesktop.DBus.Properties'

local fmt = string.format

--- Miscellaneous helpers

--[[
<!-- DTD for D-Bus Introspection data -->
<!-- (C) 2005-02-02 David A. Wheeler; released under the D-Bus licenses,
         GNU GPL version 2 (or greater) and AFL 1.1 (or greater) -->

<!-- see D-Bus specification for documentation -->

<!ELEMENT node (node|interface)*>
<!ATTLIST node name CDATA #IMPLIED>

<!ELEMENT interface (method|signal|property|annotation)*>
<!ATTLIST interface name CDATA #REQUIRED>

<!ELEMENT method (arg|annotation)*>
<!ATTLIST method name CDATA #REQUIRED>

<!ELEMENT signal (arg|annotation)*>
<!ATTLIST signal name CDATA #REQUIRED>

<!ELEMENT arg EMPTY>
<!ATTLIST arg name CDATA #IMPLIED>
<!ATTLIST arg type CDATA #REQUIRED>
<!-- Method arguments SHOULD include "direction",
     while signal and error arguments SHOULD not (since there's no point).
     The DTD format can't express that subtlety. -->
<!ATTLIST arg direction (in|out) "in">

<!-- AKA "attribute" -->
<!ELEMENT property (annotation)*>
<!ATTLIST property name CDATA #REQUIRED>
<!ATTLIST property type CDATA #REQUIRED>
<!ATTLIST property access (read|write|readwrite) #REQUIRED>

<!ELEMENT annotation EMPTY>  <!-- Generic metadata -->
<!ATTLIST annotation name CDATA #REQUIRED>
<!ATTLIST annotation value CDATA #REQUIRED>
]]

local function lom2node(doc)
   local interfaces = {}
   local nodes = {}
   for _, elt1 in ipairs(doc) do
      if type(elt1) == 'table' then
         if elt1.tag == 'interface' then
            local methods = {}
            local properties = {}
            local signals = {}
            for _, elt2 in ipairs(elt1) do
               if type(elt2) == 'table' then
                  if elt2.tag == 'method' then
                     local args = {}
                     for _, elt3 in ipairs(elt2) do
                        if type(elt3) == 'table' and elt3.tag == 'arg' then
                           args[#args+1] = {
                              name = elt3.attr.name,
                              type = elt3.attr.type,
                              direction = elt3.attr.direction,
                           }
                        end
                     end
                     methods[elt2.attr.name] = args
                  elseif elt2.tag == 'property' then
                     properties[elt2.attr.name] = {
                        access = elt2.attr.access,
                        type = elt2.attr.type,
                     }
                  elseif elt2.tag == 'signal' then
                     local args = {}
                     for _, elt3 in ipairs(elt2) do
                        if type(elt3) == 'table' and elt3.tag == 'arg' then
                           args[#args+1] = {
                              name = elt3.attr.name,
                              type = elt3.attr.type,
                           }
                        end
                     end
                     signals[elt2.attr.name] = args
                  end
               end
            end
            interfaces[#interfaces+1] = {
               name = elt1.attr.name,
               methods = methods,
               properties = properties,
               signals = signals,
            }
         elseif elt1.tag == 'node' then
            nodes[#nodes+1] = elt1.attr.name
         end
      end
   end
   return {
      interfaces = interfaces,
      nodes = nodes,
   }
end

function lsdbus.xml_fromfile(filename)
   local f = assert(io.open(filename, 'r'))
   local doc = assert(lom.parse(f))
   f:close()
   return lom2node(doc)
end

function lsdbus.xml_fromstr(str)
   local doc = assert(lom.parse(str))
   return lom2node(doc)
end

--- Find the given interface in a node table
-- return the interface if found
function lsdbus.find_intf(node, interface)
   for _,intf in ipairs(node.interfaces) do
      if intf.name == interface then
	 return intf
      end
   end
end

function lsdbus.throw(name, format, ...)
   error(name .."|"..fmt(format, ...), 2)
end

-- backwards compat
lsdbus.tovariant = common.tovariant
lsdbus.tovariant2 = common.tovariant2

return lsdbus
