
if _VERSION < "Lua 5.3" then
   require("compat53")
end

local lsdbus = require "lsdbus.core"

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

--- encode an arbitrary Lua datastructure into a lsdb variant table
-- the value returned from this function can be directly passed as a
-- second argument after a 'v' parameter.
-- example
--   utils.pp(tovariant{a=1,b={foo='hi'}}) -> {"a{sv}",{a={"x",1},b={"a{sv}",{foo={"s","hi"}}}}}
-- roundtrip:
--   utils.pp(b:testmsg('v', tovariant{a=1,b={foo='hi'}})) -> {a=1,b={foo="hi"}}
--
-- @param val value to encode
-- @return lsdbus variant table
function lsdbus.tovariant(val)
   local function is_array(t)
      for k in pairs(t) do
	 if math.type(k) ~= 'integer' then return false end
      end
      return true
   end

   local typ = type(val)

   if typ == 'number' then
      if math.type(val) == 'integer' then
	 return { 'x', val }
      else
	 return { 'd', val }
      end
   elseif typ == 'string' then
      return { 's', val }
   elseif typ == 'boolean' then
      return { 'b', val }
   elseif typ == 'table' then
      if is_array(val) then
	 local res = {}
	 for i,v in pairs(val) do res[i] = lsdbus.tovariant(v) end
	 return { 'a{iv}', res }
      else
	 local res = {}
	 for k,v in pairs(val) do res[k] = lsdbus.tovariant(v) end
	 return { 'a{sv}', res }
      end
   else
      error(string.format("unsupported type %s", typ))
   end
end

--- encode an arbitrary Lua datastructure into a lsdb variant table
--- but only return the actual variant table, not the typestr.
-- This is useful to return variants from property get/set or methods
-- where the variant typestr is already added by the server method.
function lsdbus.tovariant2(val)
   local r = lsdbus.tovariant(val)
   return r[2]
end

function lsdbus.throw(name, format, ...)
   error(name .."|"..fmt(format, ...), 2)
end

return lsdbus
