-- lsdbus.expat: D-Bus introspection XML parser using luaexpat (lxp.lom).
-- Loaded by lsdbus when the mxml C backend is not compiled in.
-- Contributed by Francois Perrad (fperrad/expat branch).

local lom = require("lxp.lom")

local M = {}

local function lom2node(doc)
   local interfaces = {}
   local nodes = {}
   for _, elt1 in ipairs(doc) do
      if type(elt1) == 'table' then
         -- skip malformed elements without mandatory name attribute
         -- (here and below), like the mxml backend does
         if elt1.tag == 'interface' and elt1.attr.name then
            local methods = {}
            local properties = {}
            local signals = {}
            for _, elt2 in ipairs(elt1) do
               if type(elt2) == 'table' and elt2.attr.name then
                  if elt2.tag == 'method' then
                     local args = {}
                     for _, elt3 in ipairs(elt2) do
                        if type(elt3) == 'table' and elt3.tag == 'arg' then
                           args[#args+1] = {
                              name      = elt3.attr.name,
                              type      = elt3.attr.type,
                              direction = elt3.attr.direction,
                           }
                        end
                     end
                     methods[elt2.attr.name] = args
                  elseif elt2.tag == 'property' then
                     properties[elt2.attr.name] = {
                        access = elt2.attr.access,
                        type   = elt2.attr.type,
                     }
                  elseif elt2.tag == 'signal' then
                     local args = {}
                     for _, elt3 in ipairs(elt2) do
                        if type(elt3) == 'table' and elt3.tag == 'arg' then
                           args[#args+1] = {
                              name = elt3.attr.name,
                              type = elt3.attr.type,
                           }
                        end
                     end
                     signals[elt2.attr.name] = args
                  end
               end
            end
            interfaces[#interfaces+1] = {
               name       = elt1.attr.name,
               methods    = methods,
               properties = properties,
               signals    = signals,
            }
         elseif elt1.tag == 'node' and elt1.attr.name then
            nodes[#nodes+1] = elt1.attr.name
         end
      end
   end
   return { name=doc.attr.name, interfaces=interfaces, nodes=nodes }
end

function M.xml_fromfile(filename)
   local f = assert(io.open(filename, 'r'))
   local xml = f:read("*a")
   f:close()
   return lom2node(assert(lom.parse(xml)))
end

function M.xml_fromstr(str)
   return lom2node(assert(lom.parse(str)))
end

return M
