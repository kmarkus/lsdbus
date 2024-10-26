--
-- Proxy: client convenience object
--

local core = require("lsdbus.core")
local err = require("lsdbus.error")
local common = require("lsdbus.common")

local met2its, met2ots = common.met2its, common.met2ots
local fmt = string.format
local unpack = table.unpack or unpack

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

function proxy:error(err_, msg)
   self._error(self, err_, msg)
   error(fmt("%s: %s (%s, %s, %s)", err_, msg or "-", self._srv, self._obj, self._intf.name))
end

-- lowlevel plumbing method
function proxy:xcall(i, m, ts, ...)
   local ret = { self._bus:call(self._srv, self._obj, i, m, ts, ...) }
   if not ret[1] then
      self:error(ret[2][1], fmt("calling %s(%s) failed: %s", m, ts, ret[2][2]))
   end
   return unpack(ret, 2)
end

function proxy:call(m, ...)
   local mtab = self._intf.methods[m]
   if not mtab then
      self:error(err.UNKNOWN_METHOD, fmt("call: no method %s", m))
   end
   local its = met2its(mtab)
   return self:xcall(self._intf.name, m, its, ...)
end

function proxy:__call(m, ...) return self:call(m, ...) end

function proxy:callr(m, ...)
   local mtab = self._intf.methods[m]
   if not mtab then
      self:error(err.UNKNOWN_METHOD, fmt("callr: no method %s", m))
   end
   local its = met2its(mtab)

   local ret = { self._bus:callr(self._srv, self._obj, self._intf.name, m, its, ...) }
   if not ret[1] then
      self:error(ret[2][1], fmt("callr %s(%s) failed: %s", m, its, ret[2][2]))
   end
   return unpack(ret, 2)
end

function proxy:call_async(m, cb, ...)
   local mtab = self._intf.methods[m]
   if not mtab then
      self:error(err.UNKNOWN_METHOD, fmt("call_async: no method %s", m))
   end
   local its = met2its(mtab)
   return self._bus:call_async(cb, self._srv, self._obj, self._intf.name, m, its, ...)
end

-- call with argument table
function proxy:callt(m, argtab)
   local mtab = self._intf.methods[m]
   local args = {}
   argtab = argtab or {}

   if not mtab then
      self:error(err.UNKNOWN_METHOD, fmt("callt: no method %s", m))
   end
   for _,a in ipairs(mtab) do
      if a.direction ~= 'out' then
	 if not a.name then
	    self:error(err.INVALID_ARGS, fmt("callt: unnamed in-arg %i of method %s", #args+1, m))
	 end
	 if argtab[a.name] == nil then
	    self:error(err.INVALID_ARGS, fmt("callt: argument %s missing", a.name))
	 end
	 args[#args+1] = argtab[a.name]
      end
   end
   return self:xcall(self._intf.name, m, met2its(mtab), unpack(args))
end

-- like callt, but return results as a table too
-- if there are no out-args, nil is returned
function proxy:calltt(m, argtab)
   local res = { self:callt(m, argtab) }

   local mtab = self._intf.methods[m]
   local restab = {}
   local rescnt = 0

   for _,a in ipairs(mtab) do
      if a.direction == 'out' then
	 rescnt = rescnt + 1
	 if not a.name then
	    self:error(err.INVALID_ARGS, fmt("callt: unnamed out-arg %i of method %s", rescnt, m))
	 end
	 if res[rescnt] == nil then
	    self:error(err.INVALID_ARGS, fmt("callt: result %i '%s' missing", rescnt, a.name))
	 end
	 restab[a.name] = res[rescnt]
      end
   end

   return (rescnt > 0) and restab or nil
end


function proxy:Get(k)
   if not self._intf.properties[k] then
      self:error(err.UNKOWN_PROPERTY, fmt("Get: unknown property %s", k))
   end
   return self:xcall(prop_if, 'Get', 'ss', self._intf.name, k)
end

function proxy:Set(k, ...)
   if not self._intf.properties[k] then
      self:error(err.UNKOWN_PROPERTY, fmt("Set: unknown property %s", k))
   end

   return self:xcall(prop_if, 'Set', 'ssv', self._intf.name, k, { self._intf.properties[k].type, ... })
end

function proxy:SetAV(k, value)
   local ptab = self._intf.properties[k]

   if not ptab then
      self:error(err.UNKOWN_PROPERTY, fmt("Set: unknown property %s", k))
   end

   local t = ptab.type

   if t == "a{sv}" or t == "a{iv}" or t == "av" then
      value = common.tovariant2(value)
   elseif ptab.type == "v" then
      value = common.tovariant(value)
   end

   return self:xcall(prop_if, 'Set', 'ssv', self._intf.name, k, { self._intf.properties[k].type, value })
end


function proxy:GetAll(filter)
   local p = self:xcall(prop_if, 'GetAll', 's', self._intf.name)

   if filter == nil then
      return p
   end

   local ft = type(filter)

   if ft ~= 'string' and ft ~= 'function' then
      self:error(err.INVALID_ARGS, fmt("GetAll: invalid filter parameter type %s", ft))
   end

   local pred = filter

   if ft == 'string' then
      if filter=='read' or filter=='write' or filter=='readwrite' then
	 pred = function (_,_,d) return d.access == filter end
      else
	 self:error(err.INVALID_ARGS, fmt("GetAll: invalid filter type %s", filter))
      end
   end

   local pf = {}

   for k,v in pairs(p) do
      if pred(k,v,self._intf.properties[k]) then pf[k] = v end
   end

   return pf
end

function proxy:SetAll(t)
   for k,v in pairs(t) do self:Set(k,v) end
end

function proxy:Ping()
   return self._bus:call(self._srv, self._obj, peer_if, 'Ping')
end

function proxy:HasProperty(p)
   if self._intf.properties[p] then return true else return false end
end

function proxy:HasMethod(m)
   if self._intf.methods[m] then return true else return false end
end

function proxy:HasSignal(s)
   if self._intf.signals[s] then return true else return false end
end

function proxy:__newindex(k, v) self:Set(k, v) end

function proxy:__index(k) return proxy[k] or proxy.Get(self, k) end

function proxy:__tostring()
   local res = {}
   res[#res+1] = fmt("srv: %s, obj: %s, intf: %s", self._srv, self._obj, self._intf.name)

   res[#res+1] = "Methods:"
   for n,m in pairs(self._intf.methods) do
      res[#res+1] = fmt("  %s (%s) -> %s", n, met2its(m), met2ots(m))
   end

   res[#res+1] = "Properties:"
   for n,p in pairs(self._intf.properties) do
      res[#res+1] = fmt("  %s: %s, %s", n, p.type, p.access)
   end

   res[#res+1] = "Signals:"
   for n,s in pairs(self._intf.signals) do
      res[#res+1] = fmt("  %s: %s", n, common.signal2ts(s))
   end

   return table.concat(res, "\n")
end

local function proxy_introspect(o)
   local ret, xml = o._bus:call(o._srv, o._obj, introspect_if, 'Introspect')
   if not ret then
      o:error(xml[1], fmt("introspection failed: %s", xml[2]))
   end
   return core.xml_fromstr(xml)
end

function proxy.new(bus, srv, obj, intf, opts)
   local function introspect(o)
      local node = proxy_introspect(o)
      for _,i in ipairs(node.interfaces) do
	 if i.name == intf then
	    o._intf = i
	    return
	 end
      end
      o:error(err.UNKNOWN_INTERFACE, "no such interface")
   end

   opts = opts or {}
   opts.error = opts.error or function() return end

   assert(type(bus)=='userdata', "missing or invalid bus arg")
   assert(type(srv)=='string', "missing or invalid srv arg")
   assert(type(obj)=='string', "missing or invalid obj arg")
   assert(type(opts)=='table', "invalid opts arg")
   assert(intf~=nil, "missing intf arg")

   local o = { _bus=bus, _srv=srv, _obj=obj, _intf=intf, _error=opts.error }
   setmetatable(o, proxy)

   if type(intf) == 'string' then
      o._intf = { name = intf }
      introspect(o)
   end

   o._intf.methods = o._intf.methods or {}
   o._intf.properties = o._intf.properties or {}
   o._intf.signals = o._intf.signals or {}

   return o
end

return proxy
