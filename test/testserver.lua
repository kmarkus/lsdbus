local lu=require("luaunit")
local lsdb = require("lsdbus")
local utils = require("utils")
local fmt = string.format
local proxy = lsdb.proxy

local testconf = debug.getregistry()['lsdbus.testconfig']

TestServer = {}

local b, p1, p2, p3

-- peer
local P = {
   srv='lsdbus.test',
   path='/',
   intf='lsdbus.test.testintf0'
}

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

function TestServer:TestCallAsync()
   local function assert_call_async(proxy, func, argtab, restab)
      local have_res = false

      local function cb (_, ...)
	 lu.assert_equals({...}, restab)
	 have_res = true
      end

      proxy:call_async(func, cb, table.unpack(argtab))

      for _=1,10 do
	 if have_res then break end
	 b:run(100*1000)
      end

      lu.assert_true(have_res, fmt("no async callback for %s", func))
   end

   assert_call_async(p1, 'pow', {4}, {16})
   assert_call_async(p1, 'pow', {9}, {81})
   assert_call_async(p1, 'concat', {"monkey", "puzzle"}, {"monkeypuzzle"})
   assert_call_async(p1, 'thunk', {}, {})
   assert_call_async(p1, 'getarray', {10}, {{"1", "2", "3", "4", "5", "6", "7", "8", "9", "10"}})
   assert_call_async(p1, 'getdict', {5}, {{key1="value1", key2="value2", key3="value3", key4="value4", key5="value5"}})

   assert_call_async(p1, 'FailWithDBusError', {},
		     {"__error__", {"lsdbus.test.BananaPeelSlip", "argh!"}})

   assert_call_async(p1, 'Fail', {},
		     { "__error__", { "org.freedesktop.DBus.Error.Failed",
				      "test/peer-testserver.lua:84: unexpectedly messed up!"}})
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

   -- accidental failure (no | syntax)
   patt = ".*oh no it crashed %(lsdbus%.test, /1, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() p1.Fail2 = true end)
   patt = ".*oh no it crashed %(lsdbus%.test, /2, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() p2.Fail2 = true end)
   patt = ".*oh no it crashed %(lsdbus%.test, /3, lsdbus%.test%.testintf0%)"
   lu.assert_error_msg_matches(patt, function() p3.Fail2 = true end)
end

-- TestServer:TestSignals
function TestServer:TestPropChanged()
   local sig = false

   local function assert_sig_recv(s,p,i,m,args)
      for _=1,10 do
	 if sig then
	    if s then lu.assert_equals(sig.s, s) end
	    if p then lu.assert_equals(sig.p, p) end
	    if i then lu.assert_equals(sig.i, i) end
	    if m then lu.assert_equals(sig.m, m) end

	    for _i=1,#args do
	       lu.assert_equals(sig.args[_i], args[_i])
	    end

	    sig = false
	    return true
	 end
	 b:run(100*1000)
      end
      lu.fail(fmt("failed to receive event %s,%s,%s,%s,args=%s", s,p,i,m,utils.tab2str(args)))
   end

   local function cb(b,s,p,i,m,...) sig = { s=s, p=p,i=i,m=m,args={...}} end

   local slot = b:match_signal(P.srv, nil, 'org.freedesktop.DBus.Properties', 'PropertiesChanged', cb)

   p1.Bar = 9999
   assert_sig_recv(nil, "/1", 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
		   { "lsdbus.test.testintf0", {Bar=9999}, {} })
   p2.Bar = 13579
   assert_sig_recv(nil, "/2", 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
		   { "lsdbus.test.testintf0", {Bar=13579}, {} })
   p3.Bar = 11111
   assert_sig_recv(nil, "/3", 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
		   { "lsdbus.test.testintf0", {Bar=11111}, {} })


   slot:unref()

   slot = b:match_signal(P.srv, nil, 'lsdbus.test.testintf0', 'HighWater', cb)

   p1('Raise')
   assert_sig_recv(nil, "/1", "lsdbus.test.testintf0", 'HighWater', { 567, "HighWaterState"})

   p2('Raise')
   assert_sig_recv(nil, "/2", "lsdbus.test.testintf0", 'HighWater', { 567, "HighWaterState"})

   p3('Raise')
   assert_sig_recv(nil, "/3", "lsdbus.test.testintf0", 'HighWater', { 567, "HighWaterState"})

   slot:unref()
end

function TestServer:TestReload()
   -- os.execute("pkill -HUP -f peer-testserver.lua")
   -- expect Propertieschanged with all readable Props
end

function TestServer:TestReload()
   -- let it fail in USR2 handler and check it stays alive
   os.execute("pkill -USR2 -f peer-testserver.lua")
   local ret, err = p1:Ping()
   if not ret then lu.assertIsTrue(ret, err[1]..": "..err[2]) end
end


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
