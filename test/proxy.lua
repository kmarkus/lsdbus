local lu=require("luaunit")
local lsdb = require("lsdbus")
local proxy = lsdb.proxy

TestProxy = {}

local b, td, hn, login

function TestProxy:setup()
   b = lsdb.open('system')

   td = proxy.new(b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1')
   hn = proxy.new(b, 'org.freedesktop.hostname1', '/org/freedesktop/hostname1', 'org.freedesktop.hostname1')
   login = proxy.new(b, 'org.freedesktop.login1', '/org/freedesktop/login1', 'org.freedesktop.login1.Manager')
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
   lu.assertIsString(td.Timezone)
   lu.assertIsString(hn.Chassis)
end

function TestProxy:TestHas()
   lu.assertIsTrue(td:HasMethod('ListTimezones'))
   lu.assertIsTrue(td:HasProperty('CanNTP'))
   lu.assertIsFalse(td:HasProperty('GuineaPig'))
end

function TestProxy:TestCallT()
   lu.assertIsTable(td:callt('ListTimezones', {}))
   login:callt('SetWallMessage', { wall_message="howdee", enable=true })
end

return TestProxy
