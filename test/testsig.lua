local lu=require("luaunit")
local lsdb = require("lsdbus")
local fmt = string.format

local MEM_USAGE_MARGIN_KB = 8
local testconfig = debug.getregistry()['lsdbus.testconfig']

local TestSig = {}

local b, slots

function TestSig:setup()
   b = lsdb.open(testconfig.bus)
   slots = {}
end

function TestSig:teardown()
   b = nil
   for _,s in ipairs(slots) do
      s:unref()
   end
end

function TestSig:TestEmitMatchSignal()
   local intf = "lsdbus.test.testemit"
   local path = "/testsig/emitmatchsignal"
   local member = "TestEmitMatch"

   local arg0 = 542
   local arg1 =  { x="three", y="four" }

   local cb_ok = false

   local function cb(b,s,p,i,m,u,t)
      lu.assert_equals(p, path)
      lu.assert_equals(i, intf)
      lu.assert_equals(m, member)
      lu.assert_equals(u, arg0)
      lu.assert_equals(t, arg1)
      cb_ok = true
   end

   slots[#slots+1] = b:match_signal(nil, path, intf, member, cb)

   b:emit_signal(path, intf, member, "ua{ss}", arg0, arg1)

   b:run(1)
   b:run(1000)

   lu.assert_true(cb_ok)
end

function TestSig:TestEmitMatch()
   local intf = "lsdbus.test.testemit"
   local path = "/testsig/emitmatch"
   local member = "TestEmitMatch"

   local ts = "ua{si}b"
   local arg0 = 542
   local arg1 =  { x=999, y=5555 }
   local arg2 = true

   local cb_ok = false

   local function cb(b,s,p,i,m,a0,a1,a2)
      lu.assert_equals(p, path)
      lu.assert_equals(i, intf)
      lu.assert_equals(m, member)
      lu.assert_equals(a0, arg0)
      lu.assert_equals(a1, arg1)
      lu.assert_equals(a2, arg2)
      cb_ok = true
   end

   local match_expr = fmt("type='signal',path='%s',interface='%s',member='%s'", path, intf, member);
   slots[#slots+1] = b:match(match_expr, cb)

   b:emit_signal(path, intf, member, ts, arg0, arg1, arg2)

   for _=1,10 do
      if cb_ok then break end
      b:run(100*1000)
   end

   lu.assert_true(cb_ok)
end

function TestSig:TestMatchSlotMemUsage()
   local function make_matches(num)
      for _=1,num do
	 local mslot = b:match_signal(nil, nil, nil, nil, function() return end)
	 lu.assert_not_nil(mslot)
	 local rawslot = mslot:rawslot()
	 lu.assert_is_function(debug.getregistry()['lsdbus.slot_table'][rawslot])

	 b:run(1); b:run(1); b:run(1);

	 mslot:unref()
      end
   end

   local num_matches = 100

   make_matches(num_matches)

   collectgarbage()
   local mem1 = collectgarbage('count')

   make_matches(num_matches)

   collectgarbage()

   local mem2 = collectgarbage('count') - MEM_USAGE_MARGIN_KB

   collectgarbage()

   -- test slot_table is empty
   lu.assert_equals(debug.getregistry()['lsdbus.slot_table'], {})

   -- test mem usage after full GC is more or less the same
   lu.assert_false(mem2>mem1, fmt("mem2 > mem1 (%s>%s)", mem2, mem1))
end


return TestSig
