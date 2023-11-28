--
-- server example showing all lsdbus bells and whistles
--
-- examples/query-server.lua will query this server
--

local lsdb = require("lsdbus")
local u = require("utils")

local DEBUG=false

local function dbg(format, ...)
   if DEBUG then print(string.format(format, ...)) end
end

local S = {
   srv='lsdbus.test',
   path='/',
   intf='lsdbus.test.testintf0'
}

local interface = {
   name="lsdbus.test.testintf0",
   methods={
      Raise={
	 handler=function(vt)
	    dbg("emiting testsignal")
	    vt:emit('HighWater', 567, "HighWaterState")
	 end
      },
      thunk={
	 handler=function(vt) dbg(u.tab2str(vt.bus:context())) end
      },
      pow={
	 {direction="in", name="x", type="i"},
	 {direction="out", name="result", type="i"},
	 handler=function(_,x) dbg("returning pow of %i", x); return x^2 end
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
	    dbg("building array of size %i", size)
	    for i=1,size do x[#x+1]=i end
	    dbg("building array done")
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
	 handler=function(vt) dbg("shutting down"); vt.bus:exit_loop() end
      },

      Fail={
	 handler=function() error("unexpectedly messed up!") end
      },

      FailWithDBusError={
	 handler=function() error("lsdbus.test.BananaPeelSlip|argh!") end
      },

      FailWithCustomDBusError={
	 {direction="in", name="error", type="s"},
	 handler=function(vt, err) error(err) end
      },
   },
   properties={
      Bar={
	 access="readwrite",
	 type="i",
	 get=function(vt) return vt.bar or 255 end,
	 set=function(vt, val)
	    local ctx = vt.bus:context()
	    dbg("setting %s Bar to %i", ctx.path, val)
	    vt.bar = val
	    vt:emitPropertiesChanged("Bar")
	 end
      },
      Time={
	 access="read",
	 type="x",
	 get=function() return os.time() end,
      },
      Wronly={
	 access="write",
	 type="s",
	 set=function(vt, x)
	    dbg("Wronly: setting to %s", x)
	    vt:emitPropertiesChanged("Wronly")
	 end,
      },
      Fail={
	 access="readwrite",
	 type="b",
	 get=function() error("lsdbus.test.testintf0.BOOM|it exploded") end,
	 set=function(_,_) error("lsdbus.test.testintf0.CRASH|it crashed")end
      },
      Fail2={
	 access="readwrite",
	 type="b",
	 get=function() error("oh no it crashed") end,
	 set=function(_,_) error("oh no it crashed") end
      },
      Fail3={
	 access="readwrite",
	 type="b",
	 get=function() error("lsdbus.test.testintf0.BOOM|") end,
	 set=function(_,_) error("|just a message")end
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

local function emit_time(b)
   b:emit_signal(S.path, S.intf, "Time", "x", os.time())

end

local b
local vt1, vt2, vt3

local function reload()
   local function filter_props(p, _)
      if p:match("Fail.*") then return false end
      return true
   end
   if vt1 then vt1:unref() end
   if vt2 then vt2:unref() end
   if vt3 then vt3:unref() end

   vt1 = lsdb.server:new(b, "/1", interface)
   vt2 = lsdb.server:new(b, "/2", interface)
   vt3 = lsdb.server:new(b, "/3", interface)

   vt1:emitAllPropertiesChanged(filter_props)
   vt2:emitAllPropertiesChanged(filter_props)
   vt3:emitAllPropertiesChanged(filter_props)
end

b = lsdb.open(os.getenv('LSDBUS_BUS') or 'default')
b:request_name(S.srv)
reload()

b:add_signal(lsdb.SIGINT, function () b:exit_loop() end)
b:add_signal(lsdb.SIGUSR1, function () vt1.var=0 end)
b:add_signal(lsdb.SIGUSR2, function () error("SIGUSR1 caught, deliberately failing") end)
b:add_signal(lsdb.SIGHUP, reload)

b:add_periodic(1*1000^2, 0, emit_time)
b:add_periodic(5*1000^2, 0, function () error("test failure in periodic callback") end)

b:loop()
