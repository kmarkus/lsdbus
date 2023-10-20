local lu=require("luaunit")
local lsdb = require("lsdbus")

local TestSig = {}

local b, slots

function TestSig:setup()
   b = lsdb.open()
   slots = {}
end

function TestSig:teardown()
   b = nil
   for _,s in ipairs(slots) do
      s:unref()
   end
end

function TestSig:TestEmitMatch()
   local intf = "lsdbus.test.testemit"
   local path = "/testsig/emitmatch"
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

return TestSig
