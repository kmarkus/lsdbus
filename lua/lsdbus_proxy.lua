--
-- Proxy: client convenience object
--

local lsdb = require("lsdbus")

local fmt = string.format
local concat = table.concat
local unpack = table.unpack

local prop_if = 'org.freedesktop.DBus.Properties'
local peer_if = 'org.freedesktop.DBus.Peer'
local introspect_if = 'org.freedesktop.DBus.Introspectable'

local proxy = {}

--[[
-- example interface description
local node = {
   {
      name = 'de.mkio.test',

      methods = {
	 Foo = {},
	 Bar = {
	    { name='x', type='s', direction='in' },
	    { name='y', type='u', direction='out' }
	 },
      },

      properties = {
	 Flip = {  type='s', access='readwrite' },
	 Flop =  { type='a{ss}', access='readwrite' },
	 Flup = { type='s', access='read' },
      }
   }
}
--]]

local function met2its(mtab)
   local i = {}
   for _,a in ipairs(mtab or {}) do
      if a.direction=='in' then i[#i+1] = a.type end
   end
   return concat(i)
end

local function met2ots(mtab)
   local o = {}
   for _,a in ipairs(mtab or {}) do
      if a.direction=='out' then o[#o+1] = a.type end
   end
   return concat(o)
end

local function sig2ts(stab)
   local s = {}
   for _,a in ipairs(stab or {}) do s[#s+1] = a.type end
   return concat(s)
end

-- lowlevel plumbing method
function proxy:xcall(i, m, ts, ...)
   local ret, res = self.bus:call(self.srv, self.obj, i, m, ts, ...)
   if not ret then
      error(fmt("calling %s (%s) failed: %s: %s (%s, %s, %s)",
		m, ts, res[1], res[2], self.srv, self.obj, i))
   end
   return res
end

function proxy:call(m, ...)
   local mtab = self.intf.methods[m]
   if not mtab then
      error(fmt("call: no method %s", m))
   end
   local its = met2its(mtab)
   return self:xcall(self.intf.name, m, its, ...)
end

function proxy:__call(m, ...) return self:call(m, ...) end

-- call with argument table
function proxy:callt(m, argtab)
   local mtab = self.intf.methods[m]
   local args = {}
   if not mtab then
      error(fmt("call: no method %s", m))
   end
   for n,a in ipairs(mtab) do
      if a.direction == 'out' then goto continue end
      if not a.name then
	 error(fmt("callt: unnamed arg #i of method %s", n, m))
      end
      if argtab[a.name] == nil then
	 error(fmt("callt: argument %s missing", a.name))
      end
      args[#args+1] = argtab[a.name]
      ::continue::
   end
   return self:xcall(self.intf.name, m, met2its(mtab), unpack(args))
end

function proxy:Get(k)
   if not self.intf.properties[k] then
      error(fmt("Get: no property %s", k))
   end
   return self:xcall(prop_if, 'Get', 'ss', self.intf.name, k)
end

function proxy:Set(k, ...)
   if not self.intf.properties[k] then
      error(fmt("Set: no property %s", k))
   end

   return self:xcall(prop_if, 'Set', 'ssv', self.intf.name, k, { self.intf.properties[k].type, ... })
end

function proxy:GetAll(filter)
   local p = self:xcall(prop_if, 'GetAll', 's', self.intf.name)

   if filter == nil then
      return p
   end

   local ft = type(filter)

   if ft ~= 'string' and ft ~= 'function' then
      error(fmt("invalid arg type %s", filter))
   end

   local pred = filter

   if ft == 'string' then
      if filter=='read' or filter=='write' or filter=='readwrite' then
	 pred = function (n,v,d) return d.access == filter end
      else
	 error(fmt("unknown string arg %s", filter))
      end
   end

   local pf = {}

   for k,v in pairs(p) do
      if pred(k,v,self.intf.properties[k]) then pf[k] = v end
   end

   return pf
end

function proxy:SetAll(t)
   for k,v in pairs(t) do self:Set(k,v) end
end

function proxy:Ping()
   return self.bus:call(self.srv, self.obj, peer_if, 'Ping')
end

function proxy:HasProperty(p)
   if self.intf.properties[p] then return true else return false end
end

function proxy:HasMethod(m)
   if self.intf.methods[m] then return true else return false end
end

function proxy:__newindex(k, v) self:Set(k, v) end

function proxy:__tostring()
   local res = {}
   res[#res+1] = fmt("srv: %s, obj: %s, intf: %s", self.srv, self.obj, self.intf.name)

   res[#res+1] = "Methods:"
   for n,m in pairs(self.intf.methods) do
      res[#res+1] = fmt("  %s (%s) -> %s", n, met2its(m), met2ots(m))
   end

   res[#res+1] = "Properties:"
   for n,p in pairs(self.intf.properties) do
      res[#res+1] = fmt("  %s: %s, %s", n, p.type, p.access)
   end

   res[#res+1] = "Signals:"
   for n,s in pairs(self.intf.signals) do
      res[#res+1] = fmt("  %s: %s", n, sig2ts(s))
   end

   return table.concat(res, "\n")
end

function proxy.introspect(bus, srv, obj)
   local ret, xml = bus:call(srv, obj, introspect_if, 'Introspect')
   if not ret then error(fmt("failed to introspect %s, %s: %s", srv, obj, xml)) end
   return lsdb.xml_fromstr(xml)
end

function proxy:new(bus, srv, obj, intf)

   if type(intf) == 'string' then
      local node = proxy.introspect(bus, srv, obj)
      for _,i in ipairs(node) do
	 if i.name == intf then
	    intf = i
	    goto continue
	 end
      end
      error(fmt("no interface %s on %s, %s", intf, srv, obj))
   end

   ::continue::
   intf.methods = intf.methods or {}
   intf.properties = intf.properties or {}

   local o = { bus=bus, srv=srv, obj=obj, intf=intf }
   setmetatable(o, self)
   self.__index = function (p, k) return self[k] or proxy.Get(p, k) end
   return o
end

return proxy
