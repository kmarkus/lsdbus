
if _VERSION < "Lua 5.3" then
   require("compat53")
end

local lsdbus = require "lsdbus.core"
local common = require("lsdbus.common")

lsdbus.proxy = require("lsdbus.proxy")
lsdbus.server = require("lsdbus.server")
lsdbus.error = require("lsdbus.error")

lsdbus.PropIntf = 'org.freedesktop.DBus.Properties'

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

function lsdbus.throw(name, format, ...)
   error(name .."|"..fmt(format, ...), 2)
end

--- Parse an lsdbus string error back into name, msg
-- if unable to parse, returns nil
-- @param err string error
-- @return dbus error name
-- @return error message
function lsdbus.parse_err(err)
   return string.match(err, "([a-zA-Z_][a-zA-Z0-9_]*%.[a-zA-Z0-9_.]+)%s*|%s*(.*)")
end

-- backwards compat
lsdbus.tovariant = common.tovariant
lsdbus.tovariant2 = common.tovariant2

return lsdbus
