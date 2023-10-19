local lu=require("luaunit")

TestMsg = require("message")
TestProxy  = require("proxy")
TestIntrospect  = require("introspect")
TestVtab = require("testvtab")
TestToVariant = require("tovariant")
TestSig = require("testsig")

runner = lu.LuaUnit.new()

os.exit( runner:runSuite() )
