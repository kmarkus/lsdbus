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

function TestMsg:TestArr()
   local args = { -2, -1, 1, 2, 3, 4, 5, 6, 7, 9 }
   local ret = b:testmsg("ai", args)
   lu.assert_equals(ret, args)
end

function TestMsg:TestArrStr()
   local ret = b:testmsg("a(ibs)", {{1, true, "one"}, { 2, false, "two"}, { 3, true, "three"}})
   lu.assert_equals(ret, {{1, "one"}, {2, "two"}, {3, "three"}})
end

function TestMsg:TestDictInt()
   local dict =	{'one', 'two', 'three'}
   local ret = b:testmsg("a{is}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestDictStr()
   local dict =	{one='number one', two='number two', three='number three'}
   local ret = b:testmsg("a{ss}", dict)
   lu.assert_equals(ret, dict)
end

function TestMsg:TestsComplexMsg()
   local ret = { b:testmsg("sais", "banana", {1,2,3,4}, "kiwi") }
   lu.assert_equals(ret, { "banana", {1,2,3,4}, "kiwi" })
end


os.exit( lu.LuaUnit.run() )
