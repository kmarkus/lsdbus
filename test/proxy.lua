local lu=require("luaunit")
local lsdb = require("lsdbus")
local proxy = require("lsdbus_proxy")

local timedate1_if = {
   name = 'org.freedesktop.timedate1',

   methods = {
      ListTimezones = {},
   },

   properties = {
      CanNTP = { type='boolean', access='read' },
      NTP = { type='boolean', access='read' },
      Timezone = { type='string', access='read' },
   }

}

local hostname1_if = {
   name = 'org.freedesktop.hostname1',

   methods = {
   },

   properties = {
      Chassis = { type='string', access='read' },
   }
}

TestProxy = {}

local b, td, hn

function TestProxy:setup()
   b = lsdb.open('default_system')

   td = proxy:new(b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', timedate1_if)
   hn = proxy:new(b, 'org.freedesktop.hostname1', '/org/freedesktop/hostname1', hostname1_if)
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

return TestProxy
