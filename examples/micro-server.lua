--
-- micro-server: the smallest complete lsdbus server
--
-- Demonstrates one method with typed args, one read property, one signal,
-- and a clean event loop. A good starting point before reading mini-server.lua.
--
-- Start the server, then use micro-client.lua or busctl to interact:
--
--   busctl --user introspect lsdbus.micro /
--   busctl --user call lsdbus.micro / lsdbus.micro Hello s "World"
--   busctl --user get-property lsdbus.micro / lsdbus.micro Counter u
--   busctl --user monitor --user  (in a separate terminal, to see signals)

local lsdb = require("lsdbus")

local intf = {
   name = "lsdbus.micro",
   methods = {
      Hello = {
         { direction="in",  name="name",  type="s" },
         { direction="out", name="reply", type="s" },
         handler = function(vt, name)
            vt.count = (vt.count or 0) + 1
            vt:emit("Greeted", vt.count)
            return "Hello, " .. name
         end
      },
   },
   properties = {
      Counter = {
         access = "read", type = "u",
         get = function(vt) return vt.count or 0 end,
      },
   },
   signals = {
      Greeted = { { name="count", type="u" } },
   },
}

local b = lsdb.open('user')
b:request_name("lsdbus.micro")
local srv = lsdb.server.new(b, "/", intf)
local sig = b:add_signal(lsdb.SIGINT, function() b:exit_loop() end)
b:loop()
