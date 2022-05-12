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

local demo_if = {
   name="lsdbus.demo.demoif0",
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
	       error("org.freedesktop.DBus.Error.InvalidArgs|empty greeting not allowed")
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
b:request_name("lsdbus.demo")
local vt = lsdb.server:new(b, "/", demo_if)
vt:emitAllPropertiesChanged()
b:loop()
