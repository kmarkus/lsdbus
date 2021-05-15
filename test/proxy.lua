local lu=require("luaunit")
local lsdb = require("lsdbus")
local proxy = require("lsdbus_proxy")

TestProxy = {}

local b, td, hn

function TestProxy:setup()
   b = lsdb.open('default_system')

   td = proxy:new(b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1')
   hn = proxy:new(b, 'org.freedesktop.hostname1', '/org/freedesktop/hostname1', 'org.freedesktop.hostname1')
end

function TestProxy:TestPing()
   local ret, err

   ret, err = td:Ping()
   if not ret then
      lu.assertIsTrue(ret, err[1]..": "..err[2])
   end

   ret, err = hn:Ping()
   if not ret then
      lu.assertIsTrue(ret, err[1]..": "..err[2])
   end
end

function TestProxy:TestSimpleCall()
   lu.assertIsTable(td('ListTimezones'))
   lu.assertEquals(td.Timezone, "Europe/Berlin")
   lu.assertEquals(hn.Chassis, "laptop")
end

function TestProxy:TestHas()
   lu.assertIsTrue(td:HasMethod('ListTimezones'))
   lu.assertIsTrue(td:HasProperty('CanNTP'))
   lu.assertIsFalse(td:HasProperty('GuineaPig'))
end

return TestProxy
