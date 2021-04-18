
lsdb = require("lsdbus")
b = lsdb.open()

b:call('org.freedesktop.UPower',
       '/org/freedesktop/UPower',
       'org.freedesktop.DBus.Introspectable',
       'Introspect',
       "")

b:call('org.freedesktop.timedate1',
       '/org/freedesktop/timedate1',
       'org.freedesktop.timedate1',
       'ListTimezones',
       "")
