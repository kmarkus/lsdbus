--
-- Proxy: client convenience object
--

local fmt = string.format
local concat = table.concat

local prop_if = 'org.freedesktop.DBus.Properties'
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

   return self:xcall(prop_if, 'Set', 'ssv', self.intf.name, k, self.intf.properties[k].type, ...)
end

function proxy:GetAll()
   return self:xcall(prop_if, 'GetAll', 's', self.intf.name)
end

function proxy:SetAll(t)
   for k,v in pairs(t) do self:Set(k,v) end
end

function proxy:__newindex(k, v) self:Set(k, v) end

function proxy:__tostring()
   local res = {}
   res[#res+1] = fmt("srv: %s, obj: %s, intf: %s", self.srv, self.obj, self.intf.name)

   for n,p in pairs(self.intf.properties) do
      res[#res+1] = fmt("%s: %s, %s", n, p.type, p.access)
   end
   return table.concat(res, "\n")
end

function proxy:new(bus, srv, obj, intf)
   intf.methods = intf.methods or {}
   intf.properties = intf.properties or {}

   local o = { bus=bus, srv=srv, obj=obj, intf=intf }
   setmetatable(o, self)
   self.__index = function (p, k) return self[k] or proxy.Get(p, k) end
   return o
end

return proxy
