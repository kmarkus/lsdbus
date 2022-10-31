
if tonumber(_VERSION:match('Lua (%d%.%d)')) < 5.3 then
   require("compat53")
end

local lsdbus = require "lsdbus.core"

lsdbus.proxy = require("lsdbus.proxy")
lsdbus.server = require("lsdbus.server")
lsdbus.error = require("lsdbus.error")

--- Miscellaneous helpers

--- Find the given interface in a node table
-- return the interface if found, otherwise false
function lsdbus.find_intf(node, interface)
   for i,intf in ipairs(node.interfaces) do
      if intf.name == interface then
	 return intf
      end
   end
   return false
end

return lsdbus
