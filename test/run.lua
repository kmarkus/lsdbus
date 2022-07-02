local lu=require("luaunit")

TestMsg = require("message")
TestProxy  = require("proxy")
TestIntrospect  = require("introspect")
TestVtab = require("testvtab")

runner = lu.LuaUnit.new()

os.exit( runner:runSuite() )
