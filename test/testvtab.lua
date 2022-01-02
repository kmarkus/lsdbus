local lu=require("luaunit")
local lsdb = require("lsdbus")

local TestVtab = {}

local b

function TestVtab:setup()
   b = lsdb.open('user')
end

function TestVtab:TestRegObjInvalidVtab()
   local function test1() b:add_object_vtable("/", {}) end
   local function test2() b:add_object_vtable("/", { name=33 }) end
   local function test3() b:add_object_vtable("/", { name="a.b", methods="garg" }) end
   local function test4() b:add_object_vtable("/", { name="a.b", methods={ frub=0} }) end
   local function test5() b:add_object_vtable("/", { name="a.b", methods={ frub={}} }) end
   local function test6() b:add_object_vtable(
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction={}}}} }) end
   local function test7() b:add_object_vtable(
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction='in', name=true}}} }) end
   local function test8() b:add_object_vtable(
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction='in', name='foo', type=true}}} }) end
   local function test9() b:add_object_vtable(
	 "/", { name="a.b", methods={ frub={ handler=function() end, {direction='pony', name='foo', type='i'}}} }) end

   lu.assertErrorMsgContains("name: expected (interface) string but got nil", test1)
   lu.assertErrorMsgContains("name: expected (interface) string but got number", test2)
   lu.assertErrorMsgContains("methods: expected table but got string", test3)
   lu.assertErrorMsgContains("method frub: expected table but got table", test4)
   lu.assertErrorMsgContains("method frub: invalid handler, expected function, got nil", test5)
   lu.assertErrorMsgContains("method frub: arg direction not a string but table", test6)
   lu.assertErrorMsgContains("method frub: arg name not a string but boolean", test7)
   lu.assertErrorMsgContains("method frub: arg type not a string but boolean", test8)
   lu.assertErrorMsgContains("method frub: invalid direction pony", test9)
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
   b:add_object_vtable("/", intf)
   b:add_object_vtable("/", { name="a.b.c" })
   b:add_object_vtable("/", { name="a.b.c", methods={}, })
   b:add_object_vtable("/", { name="a.b.c", methods={ ick={handler=function() end}}, })
end

return TestVtab
