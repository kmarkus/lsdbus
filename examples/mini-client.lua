--
-- mini-client: proxy client for mini-server.lua
--
-- Demonstrates: typed method call, property get/set, error handling,
-- signal subscription. Start mini-server.lua before running this.

local lsdb = require("lsdbus")

local b = lsdb.open('user')
local p = lsdb.proxy.new(b, "lsdbus.mini", "/", "lsdbus.mini")

-- subscribe to Yell signal emitted by Hello
local slot = b:match_signal("lsdbus.mini", "/", "lsdbus.mini", "Yell",
   function(_, volume, msg)
      print(string.format("signal Yell: volume=%d msg=%q", volume, msg))
   end)

print("Greeting:", p.Greeting)
print("Count:", p.GreetingCount)

print("reply:", p('Hello', "World"))
print("Count:", p.GreetingCount)

-- set property; server calls emitPropertiesChanged
p.Greeting = "Howdy"
print("Greeting:", p.Greeting)
print("reply:", p('Hello', "Tex"))

-- empty greeting is rejected by the server with a D-Bus error
local ok, err = pcall(function() p.Greeting = "" end)
if not ok then
   print("[expected]", err.name)  -- server rejects empty Greeting
end

b:run(200000)  -- flush pending signals
