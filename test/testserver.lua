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
   lu.assert_equals(p3('pow', -333), 110889)
end

function TestServer:TestCallWithInOut()
   local rep = string.rep
   local s1, s2

   lu.assert_equals(p1('concat', "foo", "bar"), "foobar")

   s1, s2 = rep("foo", 1000), rep("bar", 1000)
   lu.assert_equals(p2('concat', s1, s2), s1 .. s2)

   s1, s2 = rep("☠αφ", 10000), rep("🦉🐒🦄", 10000)
   lu.assert_equals(p3('concat', s1, s2), s1 .. s2)
end

function TestServer:TestGetArray()
   local function test_getarray(p)
      local a, size
      size=0
      a = p('getarray', size)
      lu.assert_equals(#a, size)

      size=10
      a = p('getarray', size)
      lu.assert_equals(#a, size)
      lu.assert_equals(a[1], "1")
      lu.assert_equals(a[size], tostring(size))

      size=100
      a = p('getarray', size)
      lu.assert_equals(#a, size)
      lu.assert_equals(a[1], "1")
      lu.assert_equals(a[10], "10")
      lu.assert_equals(a[size], tostring(size))

      size=10000
      a = p('getarray', size)
      lu.assert_equals(#a, size)
      lu.assert_equals(a[1], "1")
      lu.assert_equals(a[size], tostring(size))
   end

   test_getarray(p1)
   test_getarray(p2)
   test_getarray(p3)
end

function TestServer:TestGetDict()
   local function test_getdict(p)
      local d, size
      size=0
      d = p('getdict', size)
      lu.assert_equals(d, {})

      size=100
      d = p('getdict', size)
      for i=1,size do
	 lu.assert_equals(d['key'..tostring(i)], 'value'..tostring(i))
      end

      size=10000
      d = p('getdict', size)
      lu.assert_equals(d['key1'], 'value1')
      lu.assert_equals(d['key10'], 'value10')
      lu.assert_equals(d['key999'], 'value999')
      lu.assert_equals(d['key'..tostring(size)], 'value'..tostring(size))
   end

   test_getdict(p1)
   test_getdict(p2)
   test_getdict(p3)
end

function TestServer:TestProps()
   p1.Bar=1
   p2.Bar=2
   p3.Bar=3

   lu.assert_equals(p1.Bar, 1)
   lu.assert_equals(p2.Bar, 2)
   lu.assert_equals(p3.Bar, 3)

   p1.Bar=47
   p2.Bar=1000
   p3.Bar=9999999

   lu.assert_equals(p1.Bar, 47)
   lu.assert_equals(p2.Bar, 1000)
   lu.assert_equals(p3.Bar, 9999999)

   lu.assert_almost_equals(p1.Time, os.time(), 1)
   lu.assert_almost_equals(p2.Time, os.time(), 1)
   lu.assert_almost_equals(p3.Time, os.time(), 1)

   p1.Wronly = "write-only-string-1"
   p2.Wronly = "write-only-string-2"
   p3.Wronly = "write-only-string-3"

   -- this is a little unexpected: reading a read-only property
   -- returns "" (or 0 for a number), but busctl treats it the same:
   -- busctl --user get-property lsdbus.test /1 lsdbus.test.testintf0 Wronly
   lu.assert_equals(p1.Wronly, "")
   lu.assert_equals(p2.Wronly, "")
   lu.assert_equals(p3.Wronly, "")

   local patt
   patt = ".*lsdbus%.test%.testintf0%.BOOM.*it exploded %(lsdbus%.test, /1, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() return p1.Fail end)
   patt = ".*lsdbus%.test%.testintf0%.CRASH.*it crashed %(lsdbus%.test, /1, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() p1.Fail = true end)

   patt = ".*lsdbus%.test%.testintf0%.BOOM.*it exploded %(lsdbus%.test, /2, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() return p2.Fail end)
   patt = ".*lsdbus%.test%.testintf0%.CRASH.*it crashed %(lsdbus%.test, /2, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() p2.Fail = true end)

   patt = ".*lsdbus%.test%.testintf0%.BOOM.*it exploded %(lsdbus%.test, /3, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() return p3.Fail end)
   patt = ".*lsdbus%.test%.testintf0%.CRASH.*it crashed %(lsdbus%.test, /3, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() p3.Fail = true end)
end

-- TestServer:TestSignals

function TestServer:TestRemoteFail()
   local function f() p1('Fail') end
   local msg = "messed up! (lsdbus.test, /1, lsdbus.test.testintf0)"
   lu.assert_error_msg_contains(msg, f)

   local function f() p2('Fail') end
   local msg = "messed up! (lsdbus.test, /2, lsdbus.test.testintf0)"
   lu.assert_error_msg_contains(msg, f)

   local function f() p3('Fail') end
   local msg = "messed up! (lsdbus.test, /3, lsdbus.test.testintf0)"
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
