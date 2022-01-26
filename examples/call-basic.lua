--
-- Some basic examples of calling dbus methods using the low-level
-- call(dest,path,intf,member) method.
--

local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('default_system')

print("UPower")
u.pp(b:call('org.freedesktop.UPower',
	    '/org/freedesktop/UPower',
	    'org.freedesktop.DBus.Introspectable',
	    'Introspect'))

print("timedata1")
u.pp(b:call('org.freedesktop.timedate1',
	    '/org/freedesktop/timedate1',
	    'org.freedesktop.timedate1',
	    'ListTimezones', ""))

print("bluez hci0 'Discovering' property")
u.pp(b:call('org.bluez',
	    '/org/bluez/hci0',
	    'org.freedesktop.DBus.Properties',
	    'Get',
	    "ss",
	    "org.bluez.Adapter1", "Discovering"))

print("bluez hci0 GetAll properties")
u.pp(b:call('org.bluez',
	    '/org/bluez/hci0',
	    'org.freedesktop.DBus.Properties',
	    'GetAll',
	    "s",
	    "org.bluez.Adapter1"))
