
if tonumber(_VERSION:match('Lua (%d%.%d)')) < 5.3 then
   require("compat53")
end

local lsdbus = require "lsdbus.core"

lsdbus.proxy = require("lsdbus.proxy")
lsdbus.server = require("lsdbus.server")
lsdbus.error = require("lsdbus.error")

return lsdbus
