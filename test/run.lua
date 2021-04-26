local lu=require("luaunit")

TestMsg = require("message")
TestProxy  = require("proxy")

os.exit( lu.LuaUnit.run() )
