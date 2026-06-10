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
   if not lsdb.xml_fromstr then lu.skip("no XML backend (USE_MXML=ON or install lua-expat for USE_EXPAT)") end
   local f = "testnode.xml"
   local node = lsdb.xml_fromfile(f)
   lu.assertIsTable(node)
   lu.assertEquals(node, testnode)
end

function TestIntrospect:TestParseXMLStr()
   if not lsdb.xml_fromstr then lu.skip("no XML backend (USE_MXML=ON or install lua-expat for USE_EXPAT)") end
   local xml = [[<node name="/com/example/sample_object0">
  <interface name="com.example.SampleInterface0">
    <property name="Bar" type="y" access="readwrite"/>
  </interface>
</node>]]
   local node = lsdb.xml_fromstr(xml)
   lu.assertIsTable(node)
   lu.assertEquals(node.name, "/com/example/sample_object0")
   lu.assertEquals(#node.interfaces, 1)
   lu.assertEquals(node.interfaces[1].properties.Bar, {type="y", access="readwrite"})
end

--- regression: elements without a name attribute used to raise
--- 'table index is nil' (and leak the mxml tree)
function TestIntrospect:TestMalformedXML()
   if not lsdb.xml_fromstr then lu.skip("no XML backend (USE_MXML=ON or install lua-expat for USE_EXPAT)") end
   local xml = [[<node>
  <interface><method name="x"/></interface>
  <interface name="a.b">
    <method/>
    <method name="M"/>
    <property type="s" access="read"/>
    <signal/>
  </interface>
  <node/>
</node>]]
   local node = lsdb.xml_fromstr(xml)
   lu.assertIsTable(node)
   lu.assertEquals(#node.interfaces, 1)
   lu.assertEquals(node.interfaces[1].name, "a.b")
   lu.assertNotNil(node.interfaces[1].methods.M)
   lu.assertNil(next(node.interfaces[1].properties))
   lu.assertNil(next(node.interfaces[1].signals))
   lu.assertEquals(#node.nodes, 0)
end

return TestIntrospect
