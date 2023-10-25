local lu=require("luaunit")
local lsdb = require("lsdbus")
local proxy = lsdb.proxy

local testconf = debug.getregistry()['lsdbus.testconfig']

TestServer = {}

local b, p1, p2, p3

function TestServer:setup()
   b = lsdb.open(testconf.bus)
   p1 = proxy:new(b, 'lsdbus.test', '/1', 'lsdbus.test.testintf0')
   p2 = proxy:new(b, 'lsdbus.test', '/2', 'lsdbus.test.testintf0')
   p3 = proxy:new(b, 'lsdbus.test', '/3', 'lsdbus.test.testintf0')
end

function TestServer:TestPing()
   local ret, err

   ret, err = p1:Ping()
   if not ret then lu.assertIsTrue(ret, err[1]..": "..err[2]) end

   ret, err = p2:Ping()
   if not ret then lu.assertIsTrue(ret, err[1]..": "..err[2]) end

   ret, err = p3:Ping()
   if not ret then lu.assertIsTrue(ret, err[1]..": "..err[2]) end
end

function TestServer:TestSimpleCalls()
   lu.assert_nil(p1('thunk'))
   lu.assert_nil(p1('Raise'))
   lu.assert_nil(p2('thunk'))
   lu.assert_nil(p2('Raise'))
   lu.assert_nil(p3('thunk'))
   lu.assert_nil(p3('Raise'))

   p1('twoin', 333, { a="yes", b="maybe" })
   p2('twoin', 444, { x="no", y="perhaps" })
   p3('twoin', 555, { x="yay", y="kinda yes no" })
end

function TestServer:TestCallWithRet()
   lu.assert_equals(p1('pow', 2), 4)
   lu.assert_equals(p2('pow', 3), 9)
   lu.assert_equals(p3('pow', 10), 100)
end

function TestServer:TestRemoteFail()
   local function f() p1('Fail') end
   local msg = "org.freedesktop.DBus.Error.Failed: calling Fail() failed: test/peer-testserver.lua:70: messed up! (lsdbus.test, /1, lsdbus.test.testintf0)"
   lu.assert_error_msg_contains(msg, f)

   local function f() p2('Fail') end
   local msg = "org.freedesktop.DBus.Error.Failed: calling Fail() failed: test/peer-testserver.lua:70: messed up! (lsdbus.test, /2, lsdbus.test.testintf0)"
   lu.assert_error_msg_contains(msg, f)

   local function f() p3('Fail') end
   local msg = "org.freedesktop.DBus.Error.Failed: calling Fail() failed: test/peer-testserver.lua:70: messed up! (lsdbus.test, /3, lsdbus.test.testintf0)"
   lu.assert_error_msg_contains(msg, f)
end

function TestServer:TestFailWithDBusError()
   local function f() p1('FailWithDBusError') end
   local msg = "lsdbus.test.BananaPeelSlip: calling FailWithDBusError() failed: argh! (lsdbus.test, /1, lsdbus.test.testintf0"
   lu.assert_error_msg_contains(msg, f)

   local function f() p2('FailWithDBusError') end
   local msg = "lsdbus.test.BananaPeelSlip: calling FailWithDBusError() failed: argh! (lsdbus.test, /2, lsdbus.test.testintf0"
   lu.assert_error_msg_contains(msg, f)

   local function f() p3('FailWithDBusError') end
   local msg = "lsdbus.test.BananaPeelSlip: calling FailWithDBusError() failed: argh! (lsdbus.test, /3, lsdbus.test.testintf0"
   lu.assert_error_msg_contains(msg, f)
end

return TestServer
