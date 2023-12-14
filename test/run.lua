#!/usr/bin/env lua

local lu=require("luaunit")

-- setup global test parameters
local r = debug.getregistry()
r['lsdbus.testconfig'] = {
   bus = os.getenv('LSDBUS_BUS') or 'default'
}

print(string.format("using bus: %s", r['lsdbus.testconfig'].bus))

TestMsg = require("message")
TestProxy  = require("proxy")
TestIntrospect  = require("introspect")
TestVtab = require("testvtab")
TestToVariant = require("tovariant")
TestSig = require("testsig")
TestServer = require("testserver")

runner = lu.LuaUnit.new()

os.exit( runner:runSuite() )
