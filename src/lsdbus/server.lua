
local common = require("lsdbus.common")

local fmt = string.format
local unpack = table.unpack

local met2its, met2ots, met2names = common.met2its, common.met2ots, common.met2names
local signal2ts, signal2names = common.signal2ts, common.signal2names

local srv = {}

--- guard a function
--
-- wrap the given function in a protected call. If the call fails, the
-- errh function is invoked with the error, backtrace and context.
--
-- In case of success, it transparently returns all results,
--
-- @param fun function to guard by calling it via pcall
-- @param errh handler to be called if an error occurs
-- @param ctx optional context, will be passed to  added to errh as second arg
local function guard(fun, errh, ctx)
   assert(type(fun) == 'function', "invalid arg 1: expected function")
   assert(type(errh) == 'function', "invalid arg 2: expected handler function")

   local backtrace

   local function wrap_error(e)
      backtrace = debug.traceback(nil, 2)
      return e
   end

   return function(...)
      local r = { xpcall(fun, wrap_error, ...) }
      if r[1] == false then
	 return errh(r[2], backtrace, ctx)
      else
	 return unpack(r, 2)
      end
   end
end

local function intf_to_vtab(intf, errh, dest)

   if errh then assert(type(errh) == 'function', "invalid error handler, expected function" ) end

   common.check_intf(intf)

   dest = dest or {}
   local g = errh and guard or function(fun) return fun end

   local methods = {}
   for n,m in pairs(intf.methods or {}) do
      local handler = g(m.handler, errh, { type='method', name=n, def=m })
      methods[n] = { sig=met2its(m), res=met2ots(m), names=met2names(m), handler=handler }
   end

   local props = {}
   for n,p in pairs(intf.properties or {}) do
      local get = p.get and g(p.get, errh, { type='property-get', name=n, obj=p }) or nil
      local set = p.set and g(p.set, errh, { type='property-set', name=n, obj=p }) or nil
      props[n] = { access=p.access, type=p.type, get=get, set=set }
   end

   local signals = {}
   for n,s in pairs(intf.signals or {}) do
      signals[n] = { sig=signal2ts(s), names=signal2names(s) }
   end

   dest.name = intf.name
   dest.methods = methods
   dest.properties = props
   dest.signals = signals

   return dest
end

--- Low level constructor, populate self as new server object
function srv:initialize(bus, path, intf, errh)
   assert(type(bus)=='userdata', "missing or invalid bus arg")
   assert(type(path)=='string', "missing or invalid path arg")
   assert(type(intf)=='table', "missing or invalid interface arg")

   self._vt = intf_to_vtab(intf, errh, self)
   self._slot = bus:add_object_vtable(path, self._vt)
   self._bus, self._path, self._intf = bus, path, intf
end

-- Create a new server object
-- @param bus bus object
-- @param path path under which to provide this interface
-- @param intf interface table
-- @param errh error handler
--
-- if the errh function is present, the method, property get and set
-- handlers are invoked using pcall. In case of error, errh is called
-- passing the original error, a backtrace and a context table of the
-- form `{ type=TYPE, name=MEMBER_NAME and obj=MEMBER_TABLE }`, where
-- TYPE is one of "propery-set", "property-get", "method"
--
-- if no error handler is present, the error will propagate to the
-- lsdbus core, where it will is caught and printed to stderr.
function srv.new(bus, path, intf, errh)
   local o = {}
   srv.initialize(o, bus, path, intf, errh)
   return setmetatable(o, { __index=srv })
end

-- direct method handler invocation without vt arg
function srv:call(m, ...)
   local mtab = self._intf.methods[m]
   if not mtab then
      error(fmt("call: no method %s", m))
   end
   return mtab.handler(self, ...)
end

-- support vt('FooMethod', ...) syntax
function srv:__call(m, ...) return self:call(m, ...) end

function srv:Get(p)
   local ptab = self._intf.properties[p]
   if not ptab then
      error(fmt("getProperty: no property %s", p))
   end
   return ptab.get(self)
end

function srv:Set(p, value)
   local ptab = self._intf.properties[p]
   if not ptab then
      error(fmt("setProperty: no property %s", p))
   end
   return ptab.set(self, value)
end

function srv:HasProperty(p)
   if (self._intf.properties or {})[p] then return true else return false end
end

function srv:HasMethod(m)
   if (self._intf.methods or {})[m] then return true else return false end
end

function srv:HasSignal(s)
   if (self._intf.signals or {})[s] then return true else return false end
end

function srv:get_interface()
   return self._intf
end

-- remove vtab and invalidate the object
function srv:unref()
   self._slot:unref()
   setmetatable(self, nil)
end

function srv:emit(signal, ...)
   local sigtab = self._vt.signals[signal]
   if not sigtab then
      error(fmt("no signal '%s' on interface %s", signal, self.name))
   end
   self._bus:emit_signal(self._path, self._intf.name, signal, sigtab.sig, ...)
end

function srv:emitPropertiesChanged(...)
   self._bus:emit_properties_changed(self._path, self.name, ...)
end

function srv:emitAllPropertiesChanged(filter)
   local props = {}
   local pred = filter or function() return true end

   if type(pred) ~= 'function' then
      error(fmt("invalid filter parameter type %s", filter))
   end

   for p,pt in pairs(self._intf.properties or {}) do
      if pt.access ~= 'write' then
	 if pred(p, pt) then props[#props+1] = p end
      end
   end
   self:emitPropertiesChanged(unpack(props))
end

return srv
