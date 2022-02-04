--
-- server example showing all lsdbus bells and whistles
--
-- examples/query-server.lua will query this server
--

local lsdb = require("lsdbus")
local u = require("utils")

local b
local bar
local vt

local interface = {
   name="lsdbus.test.testintf0",
   methods={
      Raise={
	 handler=function()
	    print("emiting")
	    b:emit_signal("/", "lsdbus.test.testintf0", "Alarm", "ia{ss}", 999, {x="one", y="two"})
	 end
      },
      thunk={
	 handler=function(x) u.pp(b:context()) end
      },
      pow={
	 {direction="in", name="x", type="i"},
	 {direction="out", name="result", type="i"},
	 handler=function(x) print("pow of ", x); return x^2 end
      },
      twoin={
	 {direction="in", name="x", type="i"},
	 {direction="in", name="y", type="a{ss}"},
	 handler=function(x,y) end
      },

      twoout={
	 {direction="out", name="x", type="i"},
	 {direction="out", name="y", type="a{ss}"},
	 handler=function(x,y) return 333, { a=1, b=2, c=3 } end
      },

      concat={
	 {direction="in", name="a", type="s"},
	 {direction="in", name="b", type="s"},
	 {direction="out", name="result", type="s"},
	 handler=function(a,b) return a..b end
      },
      getarray={
	 {direction="in", name="size", type="i"},
	 {direction="out", name="result", type="a{is}"},
	 handler=function(size)
	    local x = {}
	    for i=1,size do x[#x+1]=i end
	    return x
	 end
      },
      getdict={
	 {direction="in", name="size", type="i"},
	 {direction="out", name="result", type="a{ss}"},
	 handler=function(size)
	    local x = {}
	    for i=1,size do
	       x['key'..tostring(i)]='value'..tostring(i)
	    end
	    return x end
      },

      Shutdown = {
	 handler=function() print("shutting down"); b:exit_loop() end
      },

      Fail={
	 handler=function() error("messed up!") end
      },

      FailWithDBusError={
	 handler=function() error("lsdbus.test.BananaPeelSlip|argh!") end
      },
   },
   properties={
      Bar={
	 access="readwrite",
	 type="y",
	 get=function() return bar or 255 end,
	 set=function(v)
	    print(v)
	    bar = v
	    b:emit_properties_changed("/", "lsdbus.test.testintf0", "Bar", "Date")
	 end
      },
      Date={
	 access="read",
	 type="s",
	 get=function() return os.date() end,
      },
      Wronly={
	 access="write",
	 type="s",
	 set=function(x) print(x) end,
      },
      Fail={
	 access="readwrite",
	 type="b",
	 get=function() error("lsdbus.test.testintf0.BOOM|it exploded") end,
	 set=function(v) error("lsdbus.test.testintf0.CRASH|it crashed")end
      },
   },

   signals = {
      HighWater={
	 { name="level", type="u" },
	 { name="state", type="s" }
      },
      Dunk={},
   }


}

b = lsdb.open('user')
b:request_name("lsdbus.test")
vt = lsdb.server:new(b, "/", interface)
b:loop()
