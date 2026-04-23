--
-- maxi-server: comprehensive lsdbus server showing all major features
--
-- Demonstrates: multiple typed methods (in/out args, arrays, dicts, variants,
-- error propagation), read/write/write-only properties, signals, multiple
-- object paths, emitAllPropertiesChanged with filter, periodic signal emit,
-- SIGINT for clean exit, SIGHUP for reload.
--
-- Use maxi-client.lua or maxi-client-async.lua to exercise it, or:
--
--   lsdb-info show lsdbus.maxi,/1
--   lsdb-call lsdbus.maxi,/1,lsdbus.maxi,pow "{x=7}"
--   lsdb-call lsdbus.maxi,/1,lsdbus.maxi,Shutdown

local lsdb = require("lsdbus")
local u = require("utils")

local interface = {
   name="lsdbus.maxi",
   methods={
      Raise={
         handler=function(vt)
            print("emitting HighWater")
            vt:emit('HighWater', 99, "alarm")
         end
      },
      thunk={
         handler=function(vt) u.pp(vt._bus:context()) end
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
            return x
         end
      },

      Shutdown = {
         handler=function(vt) print("shutting down"); vt._bus:exit_loop() end
      },

      Fail={
         handler=function() error("messed up!") end                          -- [expected] generic error → org.freedesktop.DBus.Error.Failed
      },

      FailWithDBusError={
         handler=function() error("lsdbus.maxi.BananaPeelSlip|argh!") end   -- [expected] "name|msg" format → custom D-Bus error name
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
      Fail={                                          -- [expected] get/set both error; skipped by filter_props below
         access="readwrite",
         type="b",
         get=function() error("lsdbus.maxi.BOOM|it exploded") end,
         set=function(_,_) error("lsdbus.maxi.CRASH|it crashed") end
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

-- Fail property getter intentionally errors; exclude it from emitAllPropertiesChanged
local function filter_props(p, _) return p ~= "Fail" end

local b = lsdb.open('user')
b:request_name("lsdbus.maxi")

local vt1 = lsdb.server.new(b, "/1", interface)
local vt2 = lsdb.server.new(b, "/2", interface)

vt1:emitAllPropertiesChanged(filter_props)
vt2:emitAllPropertiesChanged(filter_props)

local function reload()
   print("SIGHUP: reloading")
   vt1:unref(); vt2:unref()
   vt1 = lsdb.server.new(b, "/1", interface)
   vt2 = lsdb.server.new(b, "/2", interface)
   vt1:emitAllPropertiesChanged(filter_props)
   vt2:emitAllPropertiesChanged(filter_props)
end

local sig_int  = b:add_signal(lsdb.SIGINT, function() print("SIGINT: exiting"); b:exit_loop() end)
local sig_hup  = b:add_signal(lsdb.SIGHUP, reload)
local periodic = b:add_periodic(5*1000^2, 0, function()
   vt1:emit('HighWater', 42, "nominal")
end)

b:loop()
