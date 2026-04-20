
if _VERSION < "Lua 5.3" then
   require("compat53")
end

local lsdbus = require "lsdbus.core"
local common = require("lsdbus.common")

lsdbus.proxy = require("lsdbus.proxy")
lsdbus.server = require("lsdbus.server")
lsdbus.error = require("lsdbus.error")

lsdbus.PropIntf = 'org.freedesktop.DBus.Properties'

local fmt = string.format

--- Miscellaneous helpers

--- Find the given interface in a node table
-- return the interface if found
function lsdbus.find_intf(node, interface)
   for _,intf in ipairs(node.interfaces) do
      if intf.name == interface then
	 return intf
      end
   end
end

function lsdbus.throw(name, format, ...)
   error(name .."|"..fmt(format, ...), 2)
end

--- Parse an lsdbus string error back into name, msg
-- if unable to parse, returns nil
-- @param err string error
-- @return dbus error name
-- @return error message
function lsdbus.parse_err(err)
   return string.match(err, "([a-zA-Z_][a-zA-Z0-9_]*%.[a-zA-Z0-9_.]+)%s*|%s*(.*)")
end

--- Standard D-Bus interfaces, ignored during auto-resolution
--- unless explicitly specified.
local stdif = {
   ['org.freedesktop.DBus.Properties'] = true,
   ['org.freedesktop.DBus.Introspectable'] = true,
   ['org.freedesktop.DBus.Peer'] = true,
}

lsdbus.stdif = stdif

--- Find a unique proxy for a possibly incomplete (s, p, i) spec.
-- Empty strings are treated as wildcards resolved via introspection.
-- @param bus bus connection
-- @param s service name or substring
-- @param p object path or ""
-- @param i interface name or ""
-- @return true, proxy if a unique match is found
-- @return false, {{s,p,i},...} candidates otherwise
function lsdbus.find_proxy(bus, s, p, i)
   if s == "" then return false, {} end

   -- resolve service: try exact name, then substring match
   local srv
   local ret = bus:call('org.freedesktop.DBus', '/',
      'org.freedesktop.DBus', 'GetNameOwner', 's', s)
   if ret then
      srv = s
   else
      local _, names = bus:call('org.freedesktop.DBus', '/',
         'org.freedesktop.DBus', 'ListNames')
      local matches = {}
      for _, n in ipairs(names) do
         if n:sub(1, 1) ~= ':' and n:find(s, 1, true) then
            matches[#matches + 1] = n
         end
      end
      if #matches == 1 then
         srv = matches[1]
      else
         local cands = {}
         for _, n in ipairs(matches) do
            cands[#cands + 1] = { n, "", "" }
         end
         return false, cands
      end
   end

   -- introspect and collect matching (path, interface) pairs
   local objects = common.introspect(bus, srv)
   local cands = {}

   for _, o in ipairs(objects) do
      local pmatch = false
      if p == "" then
         pmatch = true
      elseif o.path == p then
         pmatch = true
      elseif o.path:find(p, 1, true) then
         pmatch = true
      end

      if pmatch then
         for _, intf in ipairs(o.node.interfaces) do
            local imatch = false
            if i == "" then
               imatch = not stdif[intf.name]
            elseif intf.name == i then
               imatch = true
            elseif intf.name:find(i, 1, true) then
               imatch = true
            end
            if imatch then
               cands[#cands + 1] = { srv, o.path, intf.name }
            end
         end
      end
   end

   if #cands == 1 then
      return true, lsdbus.proxy.new(
         bus, cands[1][1], cands[1][2], cands[1][3])
   end

   return false, cands
end

-- backwards compat
lsdbus.tovariant = common.tovariant
lsdbus.tovariant2 = common.tovariant2

return lsdbus
