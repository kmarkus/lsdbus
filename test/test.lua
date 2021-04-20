local lu=require("luaunit")
local utils = require("utils")
local lsdb = require("lsdbus")
local strict = require("strict")

local unpack = table.unpack

local b = lsdb.open()

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
   local ret = b:testmsg("v", "s", s)
   lu.assert_equals(ret, s)
end

function TestMsg:TestVariantArrayOfInts()
   local arg = { 11, 22, 33, 44, 55, 66 }
   local ret = b:testmsg("vs", "ai", arg, "lumpi")
   lu.assert_equals(ret, arg)
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
   local exp_err = "bad argument #2 to 'testmsg' (string expected, got boolean)"
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
   local exp_err = "(number expected, got no value)"
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
   local exp_err = "asd"
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


os.exit( lu.LuaUnit.run() )
