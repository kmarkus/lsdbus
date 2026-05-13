-- LuaJIT-only: FFI cdata support for 't' (uint64) and 'x' (int64).
-- Under vanilla Lua the suite registers a single placeholder that
-- skips, so the report shows one skip notice instead of one per test.

local lu = require("luaunit")

local TestLuaJIT = {}

if not jit then
   function TestLuaJIT:TestSuiteRequiresLuaJIT() lu.skip("") end
   return TestLuaJIT
end

local lsdb = require("lsdbus")
local ffi = require("ffi")

local testconf = debug.getregistry()['lsdbus.testconfig']
local b = lsdb.open(testconf.bus)

-- LL/ULL literals are LuaJIT-only syntax; wrapping in loadstring keeps
-- this file parseable under vanilla Lua even though this branch never
-- runs there.
local C = assert(loadstring([[
   return {
      FORTY2_ULL = 42ULL,
      NEG42_LL   = -42LL,
      ONE_ULL    = 1ULL,
      BEEF_ULL   = 0xdeadbeefULL,
      TWELVE_LL  = 12345LL,
      NEG1_LL    = -1LL,
      U64_MAX    = 0xffffffffffffffffULL,
      U64_BIG    = 0x123456789abcdef0ULL,
      I64_MAX    = 0x7fffffffffffffffLL,
      I64_MIN    = -0x8000000000000000LL,
   }
]]))()

function TestLuaJIT:TestInputUint64Small()
   lu.assert_equals(b:testmsg('t', ffi.new('uint64_t', 42)), C.FORTY2_ULL)
end

function TestLuaJIT:TestInputInt64Small()
   lu.assert_equals(b:testmsg('x', ffi.new('int64_t', -42)), C.NEG42_LL)
end

function TestLuaJIT:TestInputULLLiteral()
   lu.assert_equals(b:testmsg('t', C.ONE_ULL),  C.ONE_ULL)
   lu.assert_equals(b:testmsg('t', C.BEEF_ULL), C.BEEF_ULL)
end

function TestLuaJIT:TestInputLLLiteral()
   lu.assert_equals(b:testmsg('x', C.NEG1_LL),   C.NEG1_LL)
   lu.assert_equals(b:testmsg('x', C.TWELVE_LL), C.TWELVE_LL)
end

function TestLuaJIT:TestPlainNumberInputStillWorks()
   -- backwards compat: passing a Lua number must still work. Return is
   -- now cdata under LuaJIT, but compares equal to the number.
   lu.assert_equals(b:testmsg('t', 42),  C.FORTY2_ULL)
   lu.assert_equals(b:testmsg('x', -42), C.NEG42_LL)
end

function TestLuaJIT:TestReturnTypeIsCdata()
   lu.assert_equals(type(b:testmsg('t', 1)), 'cdata')
   lu.assert_equals(type(b:testmsg('x', 1)), 'cdata')
   lu.assert_equals(tostring(ffi.typeof(b:testmsg('t', 1))), 'ctype<uint64_t>')
   lu.assert_equals(tostring(ffi.typeof(b:testmsg('x', 1))), 'ctype<int64_t>')
end

function TestLuaJIT:TestRoundtripUint64Max()
   lu.assert_equals(b:testmsg('t', C.U64_MAX), C.U64_MAX)
end

function TestLuaJIT:TestRoundtripUint64Beyond53Bits()
   lu.assert_equals(b:testmsg('t', C.U64_BIG), C.U64_BIG)
end

function TestLuaJIT:TestRoundtripInt64Max()
   lu.assert_equals(b:testmsg('x', C.I64_MAX), C.I64_MAX)
end

function TestLuaJIT:TestRoundtripInt64Min()
   lu.assert_equals(b:testmsg('x', C.I64_MIN), C.I64_MIN)
end

function TestLuaJIT:TestRoundtripInt64NegOne()
   lu.assert_equals(b:testmsg('x', C.NEG1_LL), C.NEG1_LL)
end

function TestLuaJIT:TestInputCdataInMixedArgs()
   local r = { b:testmsg('itu', 1, ffi.new('uint64_t', 2), 3) }
   lu.assert_equals(r[1], 1)
   lu.assert_equals(r[2], ffi.new('uint64_t', 2))
   lu.assert_equals(r[3], 3)
end

function TestLuaJIT:TestInputCdataInArray()
   local arr = { ffi.new('uint64_t', 1),
                 ffi.new('uint64_t', 2),
                 ffi.new('uint64_t', 3) }
   local r = b:testmsg('at', arr)
   lu.assert_equals(r[1], ffi.new('uint64_t', 1))
   lu.assert_equals(r[2], ffi.new('uint64_t', 2))
   lu.assert_equals(r[3], ffi.new('uint64_t', 3))
end

function TestLuaJIT:TestRejectDoubleCdata()
   local function bad() b:testmsg('t', ffi.new('double', 1.5)) end
   lu.assert_error_msg_contains('integer expected', bad)
end

function TestLuaJIT:TestRejectPointerCdata()
   local function bad() b:testmsg('t', ffi.new('void *', nil)) end
   lu.assert_error_msg_contains('integer expected', bad)
end

function TestLuaJIT:TestRejectInt64InUint64Slot()
   local function bad() b:testmsg('t', ffi.new('int64_t', 42)) end
   lu.assert_error_msg_contains('integer expected', bad)
end

function TestLuaJIT:TestRejectUint64InInt64Slot()
   local function bad() b:testmsg('x', ffi.new('uint64_t', 42)) end
   lu.assert_error_msg_contains('integer expected', bad)
end

-- Smaller integer slots accept cdata too (no range check, mirroring the
-- Lua-number path). This is what makes json.decode -> b:call seamless:
-- a JSON integer can be cdata, the receiver slot may still be y/n/q/i/u.

function TestLuaJIT:TestCdataIntoByte()
   lu.assert_equals(b:testmsg('y', ffi.new('uint64_t', 42)), 42)
   lu.assert_equals(b:testmsg('y', ffi.new('int64_t',  42)), 42)
end

function TestLuaJIT:TestCdataIntoInt16()
   lu.assert_equals(b:testmsg('n', ffi.new('uint64_t', 1234)), 1234)
   lu.assert_equals(b:testmsg('n', ffi.new('int64_t',  -1234)), -1234)
end

function TestLuaJIT:TestCdataIntoUint16()
   lu.assert_equals(b:testmsg('q', ffi.new('uint64_t', 65535)), 65535)
   lu.assert_equals(b:testmsg('q', ffi.new('int64_t',  1)), 1)
end

function TestLuaJIT:TestCdataIntoInt32()
   lu.assert_equals(b:testmsg('i', ffi.new('uint64_t', 1000000)), 1000000)
   lu.assert_equals(b:testmsg('i', ffi.new('int64_t', -1000000)), -1000000)
end

function TestLuaJIT:TestCdataIntoUint32()
   lu.assert_equals(b:testmsg('u', ffi.new('uint64_t', 0xdeadbeef)), 0xdeadbeef)
   lu.assert_equals(b:testmsg('u', ffi.new('int64_t',  1)), 1)
end

function TestLuaJIT:TestCdataTruncatesInSmallSlot()
   -- 0x1FF -> 0xFF in a byte slot, matching the Lua-number truncation
   lu.assert_equals(b:testmsg('y', ffi.new('uint64_t', 0x1FF)), 0xFF)
end

return TestLuaJIT
