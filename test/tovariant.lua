local lu=require("luaunit")
local lsdb = require("lsdbus")

local testconf = debug.getregistry()['lsdbus.testconfig']

local b = lsdb.open(testconf.bus)

TestToVariant = {}

local cases = {
   1,
   true,
   "harry",
   { 1, 2, 3 },
   { "foo", "bar", "yuck" },
   { 1, true, "yack" },
   { a=1, b=2 },
   { foo={1,2,3}, bar={a='yup', b=333 } },
   -- doesn't work, array indices get converted to strings:
   -- { 1,2, bar='nope' } becomes {"1"=1, "2"=2, bar="nope"}
}

function TestToVariant.Test()
   for _,c in pairs(cases) do
      lu.assertEquals(c, b:testmsg('v', lsdb.tovariant(c)))
   end
end

return TestToVariant
