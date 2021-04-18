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

print("bluez hci0 'Discovering' property")
local r, res, res2 = b:call('org.bluez',
			   '/org/bluez/hci0',
			   'org.freedesktop.DBus.Properties',
			   'Get',
			   "ss",
			   "org.bluez.Adapter1", "Discovering")

print(r, u.tab2str(res), res2)

print("bluez hci0 GetAll properties")
local r, res = b:call('org.bluez',
		      '/org/bluez/hci0',
		      'org.freedesktop.DBus.Properties',
		      'GetAll',
		      "s",
		      "org.bluez.Adapter1")

print(r, u.tab2str(res))
