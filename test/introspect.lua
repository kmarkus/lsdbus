local lu = require("luaunit")
local lsdb = require("lsdbus")

local TestIntrospect = {}

local testnode = {
   name="/com/example/sample_object0",
   interfaces = {
      {
	 name="com.example.SampleInterface0",
	 methods={
	    Bazify={
	       {direction="in", name="bar", type="(iiu)"},
	       {direction="out", name="bar", type="v"}
	    },
	    Frobate={
	       {direction="in", name="foo", type="i"},
	       {direction="out", name="bar", type="s"},
	       {direction="out", name="baz", type="a{us}"}
	    },
	    Mogrify={{direction="in", name="bar", type="(iiav)"}}
	 },

	 properties={Bar={access="readwrite", type="y"}},
	 signals={Changed={{name="new_value", type="b"}}}
      },
   },
   nodes = {
      "child_of_sample_object",
      "another_child_of_sample_object"
   }
}


function TestIntrospect:TestReadXML()
   local f = "testnode.xml"
   local node = lsdb.xml_fromfile(f)
   lu.assertIsTable(node)
   lu.assertEquals(node, testnode)
end

return TestIntrospect
