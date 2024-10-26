local lu=require("luaunit")
local lsdb = require("lsdbus")
local proxy = lsdb.proxy

TestProxy = {}

local b, td, hn, login

function TestProxy:setup()
   local ok, ok_td, ok_hn, ok_login

   ok, b = pcall(lsdb.open, 'system')
   if not ok then lu.skip("no system bus available") end

   ok_td, td = pcall(proxy.new, b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1')
   ok_hn, hn = pcall(proxy.new, b, 'org.freedesktop.hostname1', '/org/freedesktop/hostname1', 'org.freedesktop.hostname1')
   ok_login, login = pcall(proxy.new, b, 'org.freedesktop.login1', '/org/freedesktop/login1', 'org.freedesktop.login1.Manager')

   if not ok_td or not ok_hn or not ok_login then
      lu.skip("timedate, hostname or login services unavailable")
   end
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
