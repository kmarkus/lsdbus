local u = require("utils")
local lsdb = require("lsdbus")
local b = lsdb.open()

print("UPower")
u.pp(b:call('org.freedesktop.UPower',
	    '/org/freedesktop/UPower',
	    'org.freedesktop.DBus.Introspectable',
	    'Introspect'))

print("timedata1")
u.pp({b:call('org.freedesktop.timedate1',
	     '/org/freedesktop/timedate1',
	     'org.freedesktop.timedate1',
	     'ListTimezones',
	     "")})
