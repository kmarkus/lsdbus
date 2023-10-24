local common = require("lsdbus.common")

local fmt = string.format
local met2its, met2ots, met2names = common.met2its, common.met2ots, common.met2names
local signal2ts, signal2names = common.signal2ts, common.signal2names

local srv = {}

function srv.__index(_, k)
   return srv[k]
end

-- create the compact vtab format required by bus:add_object_vtable
local function intf_to_vtab(intf)
   common.check_intf(intf)

   local methods = {}
   for n,m in pairs(intf.methods or {}) do
      methods[n] = { sig=met2its(m), res=met2ots(m), names=met2names(m), handler=m.handler }
   end

   local signals = {}
   for n,s in pairs(intf.signals or {}) do
      signals[n] = { sig=signal2ts(s), names=signal2names(s) }
   end

   return { name = intf.name, methods=methods, properties=intf.properties, signals=signals }
end

function srv:new(bus, path, intf)
   local vtab =	intf_to_vtab(intf)
   local slot = bus:add_object_vtable(path, vtab)
   vtab.bus = bus
   vtab.slot = slot
   vtab.path = path
   vtab.intf = intf
   setmetatable(vtab, self)
   return vtab
end

-- remove vtab and invalidate the object
function srv:unref()
   self.slot:unref()
   setmetatable(self, nil)
end

function srv:emit(signal, ...)
   local sigtab = self.signals[signal]
   if not sigtab then
      error(fmt("no signal '%s' on interface %s", signal, self.name))
   end
   self.bus:emit_signal(self.path, self.intf.name, signal, sigtab.sig, ...)
end

function srv:emitPropertiesChanged(...)
   self.bus:emit_properties_changed(self.path, self.name, ...)
end

function srv:emitAllPropertiesChanged(filter)
   local props = {}
   local pred = filter or function() return true end

   if type(pred) ~= 'function' then
      error(fmt("invalid filter parameter type %s", filter))
   end

   for p,pt in pairs(self.intf.properties or {}) do
      if pt.access ~= 'write' then
	 if pred(p, pt) then props[#props+1] = p end
      end
   end
   self:emitPropertiesChanged(table.unpack(props))
end

return srv
