local M = {}

local lsdb = require("lsdbus.core")
local concat = table.concat
local fmt = string.format

--- recursively enumerate all object paths and their interfaces
-- the result is of the following form
-- { { path=PATH, node=NODE }, ... }
-- @bus
-- @service service name
-- @return table of interfaces
function M.introspect(bus, service)
   local res = {}

   local function _introspect(path)
      local ret, xml = bus:call(service, path or '/',
				'org.freedesktop.DBus.Introspectable', 'Introspect')
      if not ret then
	 error(fmt("introspecting %s failed: %s", service, xml[2]))
      end

      local node = lsdb.xml_fromstr(xml)

      if #node.interfaces > 0 then
	 res[#res+1] = { path=(path or '/'), node=node }
      end

      for _,subnode in ipairs(node.nodes) do
	 local nextpath = (path or '') ..'/'..subnode
	 _introspect(nextpath)
      end
   end
   _introspect()
   return res
end

--- Generate a human readable method signature
-- @name name of the method
-- @mtab method introspection table
-- @return string method signature
function M.met_tostr(name, mtab)
   local iargs, oargs = {}, {}

   for _,arg in ipairs(mtab) do
      if arg.direction == 'in' then
	 iargs[#iargs+1] = fmt("%s[%s]", arg.name, arg.type)
      end

      if arg.direction =='out' then
	 oargs[#oargs+1] = fmt("%s[%s]", arg.name, arg.type)
      end
   end
   if #oargs == 0 then
      return fmt("%s(%s)", name, concat(iargs, ", "))
   else
      return fmt("%s(%s) -> %s", name, concat(iargs, ", "), concat(oargs, ', '))
   end
end

function M.prop_tostr(name, ptab)
   return fmt("%s[%s] %s", name, ptab.type, ptab.access)
end

function M.sig_tostr(name, stab)
   local args = {}
   for _,arg in ipairs(stab) do
      args[#args+1] = fmt("%s[%s]", arg.name, arg.type)
   end
   if #args == 0 then
      return name
   else
      return fmt("%s(%s)", name, concat(args, ", "))
   end
end

function M.met2its(mtab)
   local i = {}
   for _,a in ipairs(mtab or {}) do
      if a.direction=='in' then i[#i+1] = a.type end
   end
   return concat(i)
end

function M.met2ots(mtab)
   local o = {}
   for _,a in ipairs(mtab or {}) do
      if a.direction=='out' then o[#o+1] = a.type end
   end
   return concat(o)
end

function M.met2names(mtab)
   local function concat2(tab, sep, lastsep)
      if #tab == 0 then return "" end
      return concat(tab, sep) .. lastsep
   end
   local nin, nout = {}, {}
   for _,m in ipairs(mtab or {}) do
      if not m.name then error("missing argument name") end
      if m.direction=='in' then
	 nin[#nin+1] = m.name
      elseif m.direction=='out' then
	 nout[#nout+1] = m.name
      end
   end
   return concat2(nin, '\0', '\0') .. concat2(nout, '\0', '\0\0')
end

function M.signal2ts(stab)
   local s = {}
   for _,arg in ipairs(stab or {}) do s[#s+1] = arg.type end
   return concat(s)
end

function M.signal2names(stab)
   local names = {}
   for _,arg in ipairs(stab or {}) do
      if not arg.name then error("missing argument name") end
      names[#names+1] = arg.name
   end
   return concat(names, '\0') .. '\0\0'
end

function M.check_intf(intf)
   local function err(format, ...) error(fmt(format, ...)) end

   local function check_mtab(name, mtab)
      if type(mtab) ~= 'table' then
	 err("method %s: expected table, got %s", name, type(mtab))
      end
      if type(mtab.handler) ~= 'function' then
	 err("method %s: invalid handler: expected function, got %s", name, type(mtab.handler))
      end

      for i,arg in ipairs(mtab) do
	 if type(arg.direction) ~= 'string' then
	    err("method %s, arg %i: invalid direction: expected string, got %s", name, i, type(arg.direction))
	 end

	 if not (arg.direction=='in' or arg.direction=='out') then
	    err("method %s, arg %i: invalid direction %s", name, i, arg.direction)
	 end
	 if type(arg.name) ~= 'string' then
	    err("method %s, arg %i: invalid name: expected string, got %s", name, i, type(arg.name))
	 end
	 if type(arg.type) ~= 'string' then
	    err("method %s: arg %i: invalid type: expected string, got %s", name, i, type(arg.type))
	 end
      end
   end

   local function check_ptab(name, ptab)
      if type(ptab) ~= 'table' then
	 err("property %s: expected table, got %s", name, type(ptab))
      end

      if type(ptab.access) ~= 'string' then
	 err("property %s: invalid access: expected string got %s", name, type(ptab.access))
      end

      if type(ptab.type) ~= 'string' then
	 err("property %s: invalid type: expected string got %s", name, type(ptab.type))
      end

      if ptab.access ~= 'read' and ptab.access ~= 'write' and ptab.access ~= 'readwrite' then
	 err("property %s: invalid access %s", name, ptab.access)
      end

      if ptab.access == 'read' or ptab.access == 'readwrite' then
	 if type(ptab.get) ~= 'function' then
	    err("property %s: invalid get: expected function got %s", name, type(ptab.get))
	 end
      end
      if ptab.access == 'write' or ptab.access == 'readwrite' then
	 if type(ptab.set) ~= 'function' then
	    err("property %s: invalid set: expected function got %s", name, type(ptab.set))
	 end
      end
   end

   local function check_stab(name, stab)
      if type(stab) ~= 'table' then
	 err("signal %s: expected table, got %s", name, type(stab))
      end

      for i,arg in ipairs(stab) do
	 if type(arg.name) ~= 'string' then
	    err("signal %s, arg %i: invalid name: expected string, got %s", i, type(arg.name))
	 end
	 if type(arg.type) ~= 'string' then
	   err("signal %s, arg %i: invalid type: expected string, got %s", i, type(arg.type))
	 end
      end
   end

   assert(type(intf) == 'table', "invalid interface, expected table")

   if type(intf.name) ~= 'string' then
      err("invalid name: expected string, got %s", type(intf.name))
   end

   -- methods
   if intf.methods ~= nil and type(intf.methods) ~= 'table' then
      err("invalid methods: expected table, got %s", type(intf.methods))
   else
      for n,mtab in pairs(intf.methods or {}) do check_mtab(n, mtab) end
   end

   -- properties
   if intf.properties ~= nil and type(intf.properties) ~= 'table' then
      err("invalid properties: expected table, got %s", type(intf.properties))
   else
      for n,ptab in pairs(intf.properties or {}) do check_ptab(n, ptab) end
   end

   -- signals
   if intf.signals ~= nil and type(intf.signals) ~= 'table' then
      err("invalid signals: expected table, got %s", type(intf.signals))
   else
      for n,stab in pairs(intf.signals or {}) do check_stab(n, stab) end
   end

   return true
end

return M
