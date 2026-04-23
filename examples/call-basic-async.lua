--
-- call-basic-async: low-level async D-Bus method calls
--
-- Demonstrates: b:call_async(cb, dest, path, intf, member, ...) firing
-- callbacks on reply. Keeps call slots alive until the callback fires.
-- Requires UPower and timedate1 to be running on the system bus.

local u = require("utils")
local lsdb = require("lsdbus.core")

local slots = {}

local function call_async1(b, i)
   local function cb1(...)
      u.pp("callback1", i, ...)
      slots[i] = nil
   end
   return b:call_async(cb1,
		       'org.freedesktop.UPower',
		       '/org/freedesktop/UPower',
		       'org.freedesktop.DBus.Introspectable',
		       'Introspect')
end

local function call_async2(b, i)
   local function cb2(...)
      u.pp("callback2", i, ...)
      slots[i] = nil
   end
   return b:call_async(cb2,
		       'org.freedesktop.timedate1',
		       '/org/freedesktop/timedate1',
		       'org.freedesktop.timedate1',
		       'ListTimezones', "")
end

local b = lsdb.open('default_system')

for i=1,100,2 do
   slots[i] = call_async1(b, i)
   slots[i+1] = call_async2(b, i+1)

   while b:run() ~= 0 do end
end

b:loop()
