--
-- middleclass-server: OOP D-Bus service using the middleclass library
--
-- Demonstrates: mixing lsdbus.server into a middleclass class so that
-- D-Bus server objects have full OOP inheritance and instance methods.
-- Requires the 'middleclass' Lua library (luarocks install middleclass).

local lsdb = require("lsdbus")
local mc = require("middleclass")

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

-- create a server base-class by mixing in lsdb.server methods. We
-- delete the lsdbus.server.new method, since that would override the
-- middleclass new method
local server = mc.class('lsdbus.server')
server:include(lsdb.server)
server.new = nil

s1=server:new(b, "/foo", demo_if)
s2=server:new(b, "/bar", demo_if)

print("Greeting", s1:Get('Greeting')) -- -> "Hello"
s1:Set('Greeting', "Howdy")
print("Greeting", s1:Get('Greeting')) -- -> "Howdy"

s1('Hello', "Joe") -- -> Howdy Joe

print("HasProperty Greeting:", s1:HasProperty('Greeting')) -- -> true
print("HasProperty xyz:", s1:HasProperty('xyz')) -- -> false

-- interface plugin
local ifplugin = mc.class("ifplugin", server)


b:loop()
