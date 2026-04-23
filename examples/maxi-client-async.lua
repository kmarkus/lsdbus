--
-- maxi-client-async: async proxy client for maxi-server.lua
--
-- Demonstrates: call_async with per-call callbacks, handling normal
-- returns and D-Bus errors in the same callback style.
-- Optional first arg: loop count (default 1, -1 = forever).
-- Start maxi-server.lua before running this.

local u = require("utils")
local lsdb = require("lsdbus")

local tst
local cnt = 0

local function concat_cb(b, ...)
   u.pp("concat callback", b:context(), ...)
   cnt = cnt + 1
end

local function pow_cb(b, ...)
   u.pp("pow callback", b:context(), ...)
end

local function fail_cb(b, ...)   -- [expected] receives D-Bus error as first return
   u.pp("[expected] fail_cb", b:context(), {...})
end

local loops = tonumber(arg[1]) or 1

local b = lsdb.open('user')
tst = lsdb.proxy.new(b, 'lsdbus.maxi', '/1', 'lsdbus.maxi')

local s1, s2, s3, s4, s5, s6, s7, s8, s9, s10
local iter = 0

while loops == -1 or iter < loops do
   iter = iter + 1
   s1  = tst:call_async('pow',              pow_cb,                                   iter)
   s2  = tst:call_async('concat',           concat_cb,                     'a', 'b', tostring(iter))
   s3  = tst:call_async('thunk',            function(_, ...) u.pp("thunk cb",   ...) end)
   s4  = tst:call_async('twoin',            function(_, ...) u.pp("twoin cb",   ...) end, iter, {a="yes", b="maybe"})
   s5  = tst:call_async('twoout',           function(_, ...) u.pp("twoout cb",  ...) end)
   s6  = tst:call_async('getarray',         function(_, ...) u.pp("getarray cb",...) end, 10)
   s7  = tst:call_async('getdict',          function(_, ...) u.pp("getdict cb", ...) end, 10)
   s8  = tst:call_async('Raise',            function(_, ...) u.pp("raise cb",   ...) end)
   s9  = tst:call_async('Fail',             fail_cb)           -- [expected]
   s10 = tst:call_async('FailWithDBusError', fail_cb)          -- [expected]
   while b:run(1000) ~= 0 do end
end
