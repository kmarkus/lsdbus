--
-- Minimal example to illustrate methods, properties and signals
-- vtable definitions.
--
--
-- run the following script and use any D-Bus client tool to test
-- it. For example:
--
-- $ busctl --user introspect lsdbus.demo /
-- $ busctl --user get-property lsdbus.demo / lsdbus.demo.demoif0 GreetingCount
-- $ busctl --user set-property lsdbus.demo / lsdbus.demo.demoif0 Greeting s "Howdy"
-- $ busctl --user call lsdbus.demo / lsdbus.demo.demoif0 Hello s "Franz"
-- $ busctl --user set-property lsdbus.demo / lsdbus.demo.demoif0 Greeting s ""

local lsdb = require("lsdbus")

local b, srv
local greeting = "Hello"
local cnt = 0

local demo_if = {
   name="lsdbus.demo.demoif0",
   methods={
      Hello={
	 { direction="in", name="what", type="s" },
	 { direction="out", name="response", type="s" },
	 handler=function(what)
	    local msg = greeting.." "..what
	    print(msg)
	    cnt = cnt + 1
	    srv:emit('Yell', cnt, what)
	    return msg
	 end
      },
   },

   properties={
      Greeting={
	 access="readwrite",
	 type="s",
	 get=function() return greeting end,
	 set=function(v)
	    if v == "" then
	       error("org.freedesktop.DBus.Error.InvalidArgs|empty greeting not allowed")
	    end
	    greeting = v
	    b:emit_properties_changed("/", "lsdbus.demo.demoif0", "Greeting")
	 end
      },

      GreetingCount={
	 access="read",
	 type="u",
	 get=function() return cnt end,
      },
   },

   signals = {
      Yell={
	 { name="volume", type="u" },
	 { name="message", type="s" }
      },
   }
}

b = lsdb.open('user')
b:request_name("lsdbus.demo")
srv = lsdb.server:new(b, "/", demo_if)
b:loop()
