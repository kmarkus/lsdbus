
if _VERSION < "Lua 5.3" then
   require("compat53")
end

local lsdbus = require "lsdbus.core"

lsdbus.proxy = require("lsdbus.proxy")
lsdbus.server = require("lsdbus.server")
lsdbus.error = require("lsdbus.error")

local fmt = string.format

--- Miscellaneous helpers

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
	 for _,v in ipairs(val) do res[#res+1] = lsdbus.tovariant(v) end
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

function lsdbus.throw(name, format, ...)
   error({name=name, msg=fmt(format, ...)}, 2)
end

return lsdbus
