u = require("utils")
lsdb = require("lsdbus")
b = lsdb.open()


-- print("UPower")
-- b:call('org.freedesktop.UPower',
--        '/org/freedesktop/UPower',
--        'org.freedesktop.DBus.Introspectable',
--        'Introspect')

-- print("timedata1")
-- b:call('org.freedesktop.timedate1',
--        '/org/freedesktop/timedate1',
--        'org.freedesktop.timedate1',
--        'ListTimezones',
--        "")

-- print("somewhere")
-- b:call('org.somewhere.service',
--        '/org/somewhere/obj',
--        'org.somewhere.dbus.if',
--        'BlurgOp',
--        "usd", 33, "banana", 3.14)

-- print("somewhere")
-- b:call('org.somewhere.service',
--        '/org/somewhere/obj',
--        'org.somewhere.dbus.if',
--        'BlurgOp',
--        "sais", "banana", {1,2,3,4}, "kiwi")

function testmsg(typestr, ...)
   return table.pack(b:testmsg_dump('org.somewhere.service',
				    '/org/somewhere/obj',
				    'org.somewhere.dbus.if',
				    'BlurgOp',
				    typestr, ...))
end
u.pp(testmsg("sais", "banana", {1,2,3,4}, "kiwi"))


-- b:testmsg_dump('org.somewhere.service',
-- 	       '/org/somewhere/obj',
-- 	       'org.somewhere.dbus.if',
-- 	       'BlurgOp',
-- 	       "a(is)", {1,"foo",2,"bar", 3, "aa3"} )
