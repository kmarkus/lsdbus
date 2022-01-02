local lu=require("luaunit")

TestMsg = require("message")
TestProxy  = require("proxy")
TestIntrospect  = require("introspect")
TestVtab = require("testvtab")

os.exit( lu.LuaUnit.run() )
