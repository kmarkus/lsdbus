--
-- maxi-client: synchronous proxy client for maxi-server.lua
--
-- Demonstrates: proxy method calls with varied arg/return types (scalars,
-- arrays, dicts), property get/set, write-only property, signal emit,
-- and error handling for methods that intentionally fail.
-- Optional first arg: loop count (default 1, -1 = forever).
-- Start maxi-server.lua before running this.

local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('user')

local tst = lsdb.proxy.new(b, 'lsdbus.maxi', '/1', 'lsdbus.maxi')

local loops = tonumber(arg[1]) or 1
local cnt = 0
while loops == -1 or cnt < loops do
   cnt = cnt + 1
   u.pp(cnt, tst('pow', cnt))
   u.pp(cnt, tst('concat', "foo", "bar"))
   u.pp(cnt, tst('getarray', 10))
   u.pp(cnt, tst('getdict', 10))
   u.pp(cnt, tst('getarray', 1000))
   u.pp(cnt, tst('getdict', 1000))
   u.pp(cnt, tst('thunk'))
   u.pp(cnt, tst('twoin', 333, { a="yes", b="maybe" }))
   u.pp(cnt, tst('twoout'))
   u.pp(cnt, tst('Raise'))

   u.pp(cnt, "reading Bar:", tst.Bar)
   tst.Bar = cnt % 255
   u.pp(cnt, "setting Bar:", tst.Bar)
   u.pp(cnt, tst.Date)
   tst.Wronly = "Wronly " .. tostring(cnt)
end

-- [expected] generic Lua error → org.freedesktop.DBus.Error.Failed
local ok, err = pcall(function() tst('Fail') end)
if not ok then print("[expected]", err.name, err.message) end

-- [expected] "name|msg" format → custom D-Bus error name
local ok2, err2 = pcall(function() tst('FailWithDBusError') end)
if not ok2 then print("[expected]", err2.name, err2.message) end
