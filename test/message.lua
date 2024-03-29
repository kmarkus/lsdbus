local lu=require("luaunit")
local lsdb = require("lsdbus")

local testconf = debug.getregistry()['lsdbus.testconfig']

local unpack = table.unpack or unpack

local b = lsdb.open(testconf.bus)

local srv, obj, intf, met =  'org.lsdb', '/obj', 'org.lsdb', 'met'

TestMsg = {}

function TestMsg:TestBasic()
   local teststr = "a simple string"
   local ret = b:testmsg('s', teststr)
   lu.assert_equals(ret, teststr)
end

function TestMsg:TestMultiBasic()
   local args = { 33, "banana", 3.14, true }
   local ret = { b:testmsg("usdb", unpack(args)) }
   lu.assert_equals(ret, args)
end

function TestMsg:TestInts()
   local args = { 1, 2, 3, 4, 5, 6, 7, 8.001 }
   local ret = { b:testmsg("ynqiuxtd", unpack(args)) }
   lu.assert_equals(ret, args)
end

function TestMsg:TestNegInts()
   local args = { -1, -22, -33, -44.444 }
   local ret = { b:testmsg("nixd", unpack(args)) }
   lu.assert_equals(ret, args)
end

function TestMsg:TestArray()
   local args = { -2, -1, 1, 2, 3, 4, 5, 6, 7, 9 }
   local ret = b:testmsg("ai", args)
   lu.assert_equals(ret, args)
end

function TestMsg:TestArrayHuge()
   local args = {}
   for i=1,1000 do args[#args+1] = i*2 end
   local ret = b:testmsg("ai", args)
   lu.assert_equals(ret, args)
end

function TestMsg:TestArrayOfArray()
   local args = { {1,2,3}, {4,5,6}, {6,7,8} }
   local ret = b:testmsg("aai", args)
   lu.assert_equals(ret, args)
end

function TestMsg:TestsComplexMsg()
   local ret = { b:testmsg("sais", "banana", {1,2,3,4}, "kiwi") }
   lu.assert_equals(ret, { "banana", {1,2,3,4}, "kiwi" })
end

function TestMsg:TestStruct()
   local s = {1, true, "one"}
   local ret = b:testmsg("(ibs)", s)
   lu.assert_equals(ret, s)
end

function TestMsg:TestArrayOfStructs()
   local aos = {{1, true, "one"}, { 2, false, "two"}, { 3, true, "three"}}
   local ret = b:testmsg("a(ibs)", aos)
   lu.assert_equals(ret, aos)
end

function TestMsg:TestDictInt()
   local dict =	{'one', 'two', 'three'}
   local ret = b:testmsg("a{is}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictIntZeroBased()
   local dict =	{[0]='zero', 'one', 'two', 'three'}
   local ret = b:testmsg("a{is}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictStr()
   local dict =	{one='this is one', two='this is two', three='this is three'}
   local ret = b:testmsg("a{ss}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictHuge()
   local dict =	{}
   for i=1,1000 do dict['key'..tostring(i)] = 'value'..tostring(i) end
   local ret = b:testmsg("a{ss}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictWithStruct()
   local dict =	{ {99, 'ninenine'} }
   local ret = b:testmsg("a{i(is)}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictWithStruct2()
   local dict =	{ one = {11, 'this is one'},
		  two = {22, 'this is two'},
		  three = {33,'this is three'} }
   local ret = b:testmsg("a{s(is)}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictWithStruct3()
   local dict =	{ }
   local ret = b:testmsg("a{i(is)}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictWithArray()
   local dict =	{ { "krick", "krack" }, { "grit", "grat", "gronk", } }
   local ret = b:testmsg("a{uas}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestsVeryComplexMsg()
   local msg = {
      "banana",
      {1,2,3,4},
      "kiwi",
      {
	 { "fimp", "fomp", "fump" },
	 { "bimp", "bomp", "bunk" },
	 { "king", "kong", "kang" }
      }
   }
   local ret = { b:testmsg("saisaas", unpack(msg)) }
   lu.assert_equals(ret, msg)
end

function TestMsg:TestVariant()
   local s = "sumpi"
   local vin =  { "s", s }
   local ret = b:testmsg("v", vin)
   lu.assert_equals(ret, s)
   lu.assert_equals(b:testmsgr("v", vin), vin)
end

function TestMsg:TestVariantArrayOfInts()
   local arg = { 11, 22, 33, 44, 55, 66 }
   local vin = { "ai", arg }
   local ret = b:testmsg("v", vin)
   lu.assert_equals(ret, arg)
   lu.assert_equals(b:testmsgr("v", vin), vin)
end

function TestMsg:TestArrayWithVariant1()
   local vin = { { 'd', 22.2 }, { 's', "foo"}, { 'b', true} }
   local ret = b:testmsg("a{iv}", vin)
   lu.assert_equals(ret, { 22.2, "foo", true})
   lu.assert_equals(b:testmsgr("a{iv}", vin), vin)
end

function TestMsg:TestArrayWithVariant2()
   local vin = { foo={'s', "nirk"}, bar={'d', 2.718}, dunk={'b', false}}
   local ret = b:testmsg("a{sv}", vin)
   lu.assert_equals(ret, {foo="nirk", bar=2.718, dunk=false})
   lu.assert_equals(b:testmsgr("a{sv}", vin), vin)
end

function TestMsg:TestArrayWithVariant3()
   local vin = { foo={'s', "nirk"}, bar={'a{si}', { irg=1, barg=2}}}
   local vout = { foo="nirk", bar={ irg=1, barg=2}}
   local ret = b:testmsg("a{sv}", vin)
   lu.assert_equals(ret, vout)
   lu.assert_equals(b:testmsgr("a{sv}", vin), vin)
end

function TestMsg:TestArrayWithVariant4()
   local vin = { foo={'s', "nirk"}, bar={'a{sv}', { irg={'i', 1}, barg={'s', 'harry'}}}}
   local vout = { foo="nirk", bar={ irg=1, barg='harry'}}
   local ret = b:testmsg("a{sv}", vin)
   lu.assert_equals(ret, vout)
   lu.assert_equals(b:testmsgr("a{sv}", vin), vin)
end

function TestMsg:TestArrayOfVariants()
   local vin = { {'i', 1}, {'s', "forb" } }
   local vout = { 1, "forb"}

   local ret, ret2 = b:testmsg("av", vin)
   lu.assert_equals(ret, vout)
   lu.assert_equals(b:testmsgr("av", vin), vin)
end

function TestMsg:TestArrayWithVariantNested1()
   local vin = {
      a={'s', "nirk"},
      b={'av', { {'i', 1}, {'s', "forb" } }}
   }

   local vout = { a='nirk', b = {1, "forb"} }
   local ret = b:testmsg("a{sv}", vin)
   lu.assert_equals(ret, vout)
   lu.assert_equals(b:testmsgr("a{sv}", vin), vin)
end

function TestMsg:TestArrayWithVariantNested2()
   local vin = {
      a={'s', "nirk"},
      b={'a{sv}',
	 {
	    cc={'i', 1},
	    dd={'s', 'harry'},
	    ee={'a{sv}',
		{
		   ff={'i', 22},
		   gg={'s', 'sally'}
		}
	    },
	    ii={ 'av',
		 {
		    { 'u', 234 },
		    { 'a{sv}', { jjj={'i', 33}, gg={'s', "asd" } } }
		 }
	    }
	 }
      }
   }

   local vout = {
      a = "nirk",
      b = { cc=1, dd='harry',
	    ee={ ff=22, gg='sally' },
	    ii={ 234, { jjj=33, gg="asd" } }
      }
   }

   local ret = b:testmsg("a{sv}", vin)
   lu.assert_equals(ret, vout)
   lu.assert_equals(b:testmsgr("a{sv}", vin), vin)
end

-- TODO:
--   - test huge data sets
--

--
-- Test errnoneous input
--

function TestMsg:TestInvalidArg()
   local function invalid_msg()
      return b:testmsg("s", false)
   end
   local exp_err = "bad argument #3 (string expected, got boolean)"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestInvalidArg2()
   local function invalid_msg()
      return b:testmsg(")))", 1, 2, 3)
   end
   local exp_err = "invalid or unexpected typestring ')'"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestInvalidArg3()
   local function invalid_msg()
      return b:testmsg("i%^&*", 1, 2, 3)
   end
   local exp_err = "invalid or unexpected typestring '%'"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestInvalidTooFewArgs()
   local function invalid_msg()
      return b:testmsg("siq", "grunk", -4711)
   end
   local exp_err = "(integer expected, got no value)"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestInvalidNoArgs()
   local function invalid_msg()
      return b:testmsg("(siq)")
   end
   local exp_err = "not a table but no value"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestInvalidMissingStructClose()
   local function invalid_msg()
      return b:testmsg("(siq", "str", 23, 2)
   end
   local exp_err = "invalid struct type string (siq"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestInvalidMissingDictClose()
   local function invalid_msg()
      return b:testmsg("{uqi", "str")
   end
   local exp_err = "invalid dict type string {uqi"
   lu.assert_error_msg_contains(exp_err, invalid_msg)
end

function TestMsg:TestCompositeMT()
   local function typ (x)
      local t = (getmetatable(x) or {}).__name
      return t or false
   end

   lu.assert_equals(typ(b:testmsgr('(ii)', {3, 3})), "lsdbus.struct")
   lu.assert_equals(typ(b:testmsgr('ai', {1,2,3})), "lsdbus.array")
   lu.assert_equals(typ(b:testmsgr('v', {'i', 33})), "lsdbus.variant")

   local vin = {
      a={'s', "nirk"},
      b={'a{sv}',
	 {
	    cc={'i', 1},
	    ee={'a{sv}',
		{
		   ff={'i', 22},
		   gg={'s', 'sally'}
		}
	    },
	 }
      }
   }
   local ret = b:testmsgr("a{sv}", vin)

   lu.assert_equals(typ(ret.a), "lsdbus.variant")
   lu.assert_equals(typ(ret.b), "lsdbus.variant")
   lu.assert_equals(typ(ret.b[2]), "lsdbus.array")
   lu.assert_equals(typ(ret.b[2].cc), "lsdbus.variant")
   lu.assert_equals(typ(ret.b[2].ee), "lsdbus.variant")
   lu.assert_equals(typ(ret.b[2].ee[2]), "lsdbus.array")
   lu.assert_equals(typ(ret.b[2].ee[2].ff), "lsdbus.variant")
   lu.assert_equals(typ(ret.b[2].ee[2].gg), "lsdbus.variant")

end

return TestMsg
