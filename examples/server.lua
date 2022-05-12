--
-- server example showing all lsdbus bells and whistles
--
-- examples/query-server.lua will query this server
--

local lsdb = require("lsdbus")
local u = require("utils")

local interface = {
   name="lsdbus.test.testintf0",
   methods={
      Raise={
	 handler=function(vt)
	    print("emiting")
	    vt.bus:emit_signal("/", "lsdbus.test.testintf0", "Alarm", "ia{ss}", 999, {x="one", y="two"})
	 end
      },
      thunk={
	 handler=function(vt) u.pp(vt.bus:context()) end
      },
      pow={
	 {direction="in", name="x", type="i"},
	 {direction="out", name="result", type="i"},
	 handler=function(_,x) print("pow of ", x); return x^2 end
      },
      twoin={
	 {direction="in", name="x", type="i"},
	 {direction="in", name="y", type="a{ss}"},
	 handler=function(_,x,y) end
      },

      twoout={
	 {direction="out", name="x", type="i"},
	 {direction="out", name="y", type="a{ss}"},
	 handler=function(_) return 333, { a=1, b=2, c=3 } end
      },

      concat={
	 {direction="in", name="a", type="s"},
	 {direction="in", name="b", type="s"},
	 {direction="out", name="result", type="s"},
	 handler=function(_,a,b) return a..b end
      },
      getarray={
	 {direction="in", name="size", type="i"},
	 {direction="out", name="result", type="a{is}"},
	 handler=function(_,size)
	    local x = {}
	    for i=1,size do x[#x+1]=i end
	    return x
	 end
      },
      getdict={
	 {direction="in", name="size", type="i"},
	 {direction="out", name="result", type="a{ss}"},
	 handler=function(_,size)
	    local x = {}
	    for i=1,size do
	       x['key'..tostring(i)]='value'..tostring(i)
	    end
	    return x end
      },

      Shutdown = {
	 handler=function(vt) print("shutting down"); vt.bus:exit_loop() end
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
	 get=function(vt) return vt.bar or 255 end,
	 set=function(vt,val)
	    print("setting Bar to ", val)
	    vt.bar = val
	    vt:emitPropertiesChanged("Bar", "Date")
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
	 set=function(_, x) print(x) end,
      },
      Fail={
	 access="readwrite",
	 type="b",
	 get=function() error("lsdbus.test.testintf0.BOOM|it exploded") end,
	 set=function(_,_) error("lsdbus.test.testintf0.CRASH|it crashed")end
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

local b = lsdb.open('user')
b:request_name("lsdbus.test")
local vt = lsdb.server:new(b, "/", interface)
vt:emitAllPropertiesChanged(
   function(p, _) if p=="Fail" then return false else return true end end)
b:loop()
