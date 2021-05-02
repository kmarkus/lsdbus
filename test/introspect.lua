local lu = require("luaunit")
local lsdb = require("lsdbus")

local TestIntrospect = {}

function TestIntrospect:TestReadXML()
   local f = "/usr/share/dbus-1/interfaces/org.freedesktop.PackageKit.xml"
   print("parsing ", f)
   lsdb.xml_read(f)
end

return TestIntrospect
