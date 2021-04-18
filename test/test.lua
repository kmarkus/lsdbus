
lsdb = require("lsdbus")
b = lsdb.open()


print("UPower")
b:call('org.freedesktop.UPower',
       '/org/freedesktop/UPower',
       'org.freedesktop.DBus.Introspectable',
       'Introspect')

print("timedata1")
b:call('org.freedesktop.timedate1',
       '/org/freedesktop/timedate1',
       'org.freedesktop.timedate1',
       'ListTimezones',
       "")

print("somewhere")
b:call('org.somewhere.service',
       '/org/somewhere/obj',
       'org.somewhere.dbus.if',
       'BlurgOp',
       "usd", 33, "banana", 3.14)
