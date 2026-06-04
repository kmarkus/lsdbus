#!/usr/bin/env lua

local lu=require("luaunit")

-- setup global test parameters
local r = debug.getregistry()
r['lsdbus.testconfig'] = {
   bus = os.getenv('LSDBUS_BUS') or 'default'
}

local lsdbus = require("lsdbus")
print(string.format("using bus: %s, xml_backend: %s", r['lsdbus.testconfig'].bus, lsdbus.xml_backend or "none"))

TestMsg = require("message")
TestProxy  = require("proxy")
TestIntrospect  = require("introspect")
TestVtab = require("testvtab")
TestToVariant = require("tovariant")
TestSig = require("testsig")
TestServer = require("testserver")
TestEvSrc = require("testevsrc")
TestJob = require("testjob")
TestCredentials = require("testcredentials")

runner = lu.LuaUnit.new()

os.exit( runner:runSuite() )
