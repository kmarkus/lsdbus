local lu=require("luaunit")

TestMsg = require("message")
TestProxy  = require("proxy")
TestIntrospect  = require("introspect")

os.exit( lu.LuaUnit.run() )
