local lu=require("luaunit")
local lsdb = require("lsdbus")

local MEM_USAGE_MARGIN_KB = 64
local testconf = debug.getregistry()['lsdbus.testconfig']

local TestVtab = {}

local b

function TestVtab:setup()
   b = lsdb.open(testconf.bus)
end

function TestVtab:teardown()
   b = nil
end

local test_intf = {
   name="a.b.c",
   methods={
      ick={handler=function() end}
   },
   properties = {
      Foo={
	 access="readwrite",
	 type="s",
	 get=function(vt) return "Foo" end,
	 set=function(vt, val) end,
      },
   },
   signals = {
      Boom={
	 { name="message", type="s" }
      }
   }
}


function TestVtab:TestRegObjInvalidVtab()
   local function test1() lsdb.server.new(b, "/", {}) end
   local function test2() lsdb.server.new(b, "/", { name=33 }) end
   local function test3() lsdb.server.new(b, "/", { name="a.b", methods="garg" }) end
   local function test4() lsdb.server.new(b, "/", { name="a.b", methods={ frub=0} }) end
   local function test5() lsdb.server.new(b, "/", { name="a.b", methods={ frub={}} }) end
   local function test6() lsdb.server.new(b,
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction={}}}} }) end
   local function test7() lsdb.server.new(b,
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction='in', name=true}}} }) end
   local function test8() lsdb.server.new(b,
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction='in', name='foo', type=true}}} }) end
   local function test9() lsdb.server.new(b,
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction='pony', name='foo', type='i'}}} }) end

   lu.assertErrorMsgContains("invalid name: expected string, got nil", test1)
   lu.assertErrorMsgContains("invalid name: expected string, got number", test2)
   lu.assertErrorMsgContains("invalid methods: expected table, got string", test3)
   lu.assertErrorMsgContains("method frub: expected table, got number", test4)
   lu.assertErrorMsgContains("method frub: invalid handler: expected function, got nil", test5)
   lu.assertErrorMsgContains("method frub, arg 1: invalid direction: expected string, got table", test6)
   lu.assertErrorMsgContains("method frub, arg 1: invalid name: expected string, got boolean", test7)
   lu.assertErrorMsgContains("method frub: arg 1: invalid type: expected string, got boolean", test8)
   lu.assertErrorMsgContains("method frub, arg 1: invalid direction pony", test9)
end


function TestVtab:TestRegObjValidVtab()
   local intf = {
      name="lsdbus.test.testintf0",
      methods={
	 thunk={
	    handler=function(x) print("howdee thunk!") end
	 },
	 pow={
	    {direction="in", name="x", type="i"},
	    {direction="out", name="result", type="i"},
	    handler=function(x) print("pow of ", x); return x^2 end
	 },
	 twoin={
	    {direction="in", name="x", type="i"},
	    {direction="in", name="y", type="a{ss}"},
	    handler=function(x,y) return end
	 },

	 twoout={
	    {direction="out", name="x", type="i"},
	    {direction="out", name="y", type="a{ss}"},
	    handler=function(x,y) return 333, { a=1, b=2, c=3 } end
	 },

	 concat={
	    {direction="in", name="a", type="s"},
	    {direction="in", name="b", type="s"},
	    {direction="out", name="result", type="s"},
	    handler=function(a,b) return a..b end
	 },
	 getarray={
	    {direction="in", name="size", type="i"},
	    {direction="out", name="result", type="a{is}"},
	    handler=function(size)
	       local x = {}
	       for i=1,size do x[#x+1]=i end
	       return x
	    end
	 },
	 getdict={
	    {direction="in", name="size", type="i"},
	    {direction="out", name="result", type="a{ss}"},
	    handler=function(size)
	       local x = {}
	       for i=1,size do
		  x['key'..tostring(i)]='value'..tostring(i)
	       end
	       return x end
	 },
      }
   }
   self.count = self.count or 0
   self.count = self.count + 1

   lsdb.server.new(b, "/a"..tostring(self.count), intf)
   lsdb.server.new(b, "/b"..tostring(self.count), { name="a.b.c" })
   lsdb.server.new(b, "/c"..tostring(self.count), { name="a.b.c", methods={}, })
   lsdb.server.new(b, "/d"..tostring(self.count), { name="a.b.c", methods={ ick={handler=function() end}}, })
end


function TestVtab:TestVtabCleanup()
   local vt = lsdb.server.new(b, "/", test_intf)
   lu.assert_is_table(vt)
   local rawslot = vt._slot:rawslot()
   lu.assert_is_table(debug.getregistry()['lsdbus.slot_table'][rawslot])

   -- release and check via that the vt has been removed from the slot
   -- table
   vt = nil
   collectgarbage()
   lu.assert_is_nil(debug.getregistry()['lsdbus.slot_table'][rawslot])
end

function TestVtab:TestVtabExplicitCleanup()
   local function create_destroy()
      local vt = lsdb.server.new(b, "/", test_intf)
      lu.assert_is_table(vt)
      local rawslot = vt._slot:rawslot()
      lu.assert_is_table(debug.getregistry()['lsdbus.slot_table'][rawslot])

      -- release and check via that the vt has been removed from the slot
      -- table
      vt:unref()
      lu.assert_is_nil(debug.getregistry()['lsdbus.slot_table'][rawslot])
   end

   for _=1,1000 do create_destroy() end
end

-- Read VmRSS in kB from /proc/self/status (Linux only), returns nil if unavailable
local function get_rss_kb()
   local f = io.open("/proc/self/status", "r")
   if not f then return nil end
   local rss
   for line in f:lines() do
      rss = line:match("^VmRSS:%s+(%d+)")
      if rss then break end
   end
   f:close()
   return tonumber(rss)
end

-- Create N vtab objects via lsdb.server.new and immediately unref them explicitly.
-- Returns the raw slot pointers so callers can verify cleanup.
local function make_and_unref_vtabs(num, base_cnt)
   local slots = {}
   for i = 1, num do
      local vt = lsdb.server.new(b, string.format("/leak_test/%i", base_cnt + i), test_intf)
      slots[i] = vt._slot:rawslot()
      vt:unref()
   end
   return slots
end

-- GC-based lifecycle: create vtabs inside a scope and let them be collected.
-- Wrapping in a function ensures locals go out of scope after the call.
local function make_vtabs_gc(num, base_cnt)
   for i = 1, num do
      lsdb.server.new(b, string.format("/leak_gc/%i", base_cnt + i), test_intf)
   end
end

function TestVtab:TestVtabUnrefMemUsage()
   local MEM_MARGIN_KB = 64
   local N = 1000
   local cnt = 0

   -- warm-up with full batch size to pre-expand malloc arena
   make_and_unref_vtabs(N, cnt); cnt = cnt + N
   collectgarbage(); collectgarbage()

   local rss1 = get_rss_kb()
   local lua1 = collectgarbage('count')

   make_and_unref_vtabs(N, cnt); cnt = cnt + N

   collectgarbage(); collectgarbage()

   local rss2 = get_rss_kb()
   local lua2 = collectgarbage('count')

   -- slot_table and vtab_user_arg must both be empty after explicit unref
   lu.assert_equals(debug.getregistry()['lsdbus.slot_table'], {})
   lu.assert_equals(debug.getregistry()['lsdbus.vtab_user_arg'], {})

   -- Lua heap should not have grown appreciably
   lu.assert_false(lua2 - lua1 > MEM_MARGIN_KB,
      string.format("Lua heap grew by %.1f kB after %d unref'd vtabs", lua2 - lua1, N))

   -- C heap (RSS) should not have grown appreciably
   if rss1 and rss2 then
      lu.assert_false(rss2 - rss1 > MEM_MARGIN_KB,
         string.format("RSS grew by %d kB after %d unref'd vtabs (possible C leak)", rss2 - rss1, N))
   end
end

function TestVtab:TestVtabGcMemUsage()
   local MEM_MARGIN_KB = 64
   local N = 1000
   local cnt = 0

   -- warm-up with full batch size to pre-expand malloc arena
   make_vtabs_gc(N, cnt); cnt = cnt + N
   collectgarbage(); collectgarbage()

   local rss1 = get_rss_kb()
   local lua1 = collectgarbage('count')

   make_vtabs_gc(N, cnt); cnt = cnt + N

   collectgarbage(); collectgarbage()

   local rss2 = get_rss_kb()
   local lua2 = collectgarbage('count')

   lu.assert_equals(debug.getregistry()['lsdbus.slot_table'], {})
   lu.assert_equals(debug.getregistry()['lsdbus.vtab_user_arg'], {})

   lu.assert_false(lua2 - lua1 > MEM_MARGIN_KB,
      string.format("Lua heap grew by %.1f kB after %d GC'd vtabs", lua2 - lua1, N))

   if rss1 and rss2 then
      lu.assert_false(rss2 - rss1 > MEM_MARGIN_KB,
         string.format("RSS grew by %d kB after %d GC'd vtabs (possible C leak)", rss2 - rss1, N))
   end
end

function TestVtab:TestVtabMemUsage()

   local cnt=0
   local function make_vtabs(num)
      for _=1,num do
	 local vt = lsdb.server.new(b, string.format("/mem_usage/%i", cnt), test_intf)
	 lu.assert_is_table(vt)
	 local rawslot = vt._slot:rawslot()
	 lu.assert_is_table(debug.getregistry()['lsdbus.slot_table'][rawslot])
	 cnt = cnt + 1
      end
   end

   make_vtabs(3)

   collectgarbage()
   collectgarbage()

   local mem1 = collectgarbage('count')

   make_vtabs(1000)

   collectgarbage()
   collectgarbage()

   local mem2 = collectgarbage('count') - MEM_USAGE_MARGIN_KB

   -- test slot_table is empty
   lu.assert_equals(debug.getregistry()['lsdbus.slot_table'], {})

   -- test mem usage after full GC is more or less the same
   lu.assert_false(mem2>mem1, string.format("mem2 > mem1 (%s>%s)", mem2, mem1))
end


return TestVtab
