--
-- properties-changed: subscribe to PropertiesChanged signals
--
-- Demonstrates: matching org.freedesktop.DBus.Properties.PropertiesChanged,
-- which servers emit via emitPropertiesChanged() or emitAllPropertiesChanged().
-- The signal carries changed property values and a list of invalidated names.
--
-- Start mini-server.lua or maxi-server.lua first, then in another terminal:
--   busctl --user set-property lsdbus.mini / lsdbus.mini Greeting s "Hi"

local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('user')

local match = b:match_signal(
   nil,                                -- sender (any: works with mini- and maxi-server)
   nil,                                -- path   (nil = any)
   "org.freedesktop.DBus.Properties",  -- interface
   "PropertiesChanged",                -- member
   function(_, intf, changed, invalidated)
      print("PropertiesChanged on interface: " .. intf)
      if changed then
         for k, v in pairs(changed) do
            io.write(string.format("  changed:     %s = ", k))
            u.pp(v)
         end
      end
      for _, name in ipairs(invalidated or {}) do
         print("  invalidated: " .. name)
      end
   end)

local sig = b:add_signal(lsdb.SIGINT, function() b:exit_loop() end)
print("Monitoring PropertiesChanged (Ctrl+C to exit)")
b:loop()
