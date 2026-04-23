--
-- micro-client: synchronous proxy client for micro-server.lua
--
-- Demonstrates: proxy method call, property read, signal subscription.
-- Start micro-server.lua before running this.

local lsdb = require("lsdbus")

local b = lsdb.open('user')
local p = lsdb.proxy.new(b, "lsdbus.micro", "/", "lsdbus.micro")

-- subscribe to signal before calling the method
local slot = b:match_signal("lsdbus.micro", "/", "lsdbus.micro", "Greeted",
   function(_, count)
      print(string.format("signal: Greeted count=%d", count))
   end)

print("reply:", p('Hello', "World"))
print("reply:", p('Hello', "Lua"))
print("counter:", p.Counter)

b:run(100000)  -- flush pending signals
