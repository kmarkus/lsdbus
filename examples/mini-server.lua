--
-- mini-server: a concise lsdbus server covering the core concepts
--
-- Demonstrates: typed method, readwrite property with validation and
-- emitPropertiesChanged, read-only property, signal, D-Bus error propagation.
-- See mini-client.lua for a matching proxy client.
--
--   busctl --user introspect lsdbus.mini /
--   busctl --user call lsdbus.mini / lsdbus.mini Hello s "Franz"
--   busctl --user get-property lsdbus.mini / lsdbus.mini GreetingCount
--   busctl --user set-property lsdbus.mini / lsdbus.mini Greeting s "Howdy"
--   busctl --user set-property lsdbus.mini / lsdbus.mini Greeting s ""

local lsdb = require("lsdbus")

local demo_if = {
   name="lsdbus.mini",
   methods={
      Hello={
	 { direction="in", name="what", type="s" },
	 { direction="out", name="response", type="s" },
	 handler=function(vt, what)
	    local msg = (vt.greeting or "Hello").." "..what
	    print(msg)
	    vt.cnt = (vt.cnt or 0) + 1
	    vt:emit('Yell', vt.cnt, msg)
	    return msg
	 end
      },
   },

   properties={
      Greeting={
	 access="readwrite",
	 type="s",
	 get=function(vt) return vt.greeting or "Hello" end,
	 set=function(vt, val)
	    if val == "" then
	       error("org.freedesktop.DBus.Error.InvalidArgs|empty greeting not allowed") -- [expected] validation error
	    end
	    vt.greeting = val
	    vt:emitPropertiesChanged("Greeting")
	 end
      },

      GreetingCount={
	 access="read",
	 type="u",
	 get=function(vt) return vt.cnt or 0 end,
      },
   },

   signals = {
      Yell={
	 { name="volume", type="u" },
	 { name="message", type="s" }
      },
   }
}

local b = lsdb.open('user')
b:request_name("lsdbus.mini")
local vt = lsdb.server.new(b, "/", demo_if)
vt:emitAllPropertiesChanged()
local sig = b:add_signal(lsdb.SIGINT, function() b:exit_loop() end)
b:loop()
