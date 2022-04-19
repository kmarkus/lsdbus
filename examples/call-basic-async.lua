local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('default_system')
local callback
local slot
local loop = 100000*2

local function call_async1()
   return b:call_async(callback,
		       'org.freedesktop.UPower',
		       '/org/freedesktop/UPower',
		       'org.freedesktop.DBus.Introspectable',
		       'Introspect')
end

local function call_async2()
   return b:call_async(callback,
		       'org.freedesktop.timedate1',
		       '/org/freedesktop/timedate1',
		       'org.freedesktop.timedate1',
		       'ListTimezones', "")
end

function callback(...)
   if loop<0 then print("exiting loop"); b:exit_loop() end

   slot = call_async1()
   loop = loop -1
   collectgarbage('collect')
   print(slot, loop, collectgarbage('count'))
end

slot = call_async2()

-- throws EEXIST, it seems only one async call is allowed simultaneously.

-- u.pp(b:call_async(
-- 	callback,
-- 	'org.freedesktop.timedate1',
--  	'/org/freedesktop/timedate1',
--  	'org.freedesktop.timedate1',
--  	'ListTimezones', ""))

b:loop()
