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

local function fail_cb(b, ...)
   u.pp("fail_cb", b:context(), {...})
end

local b = lsdb.open('user')
tst = lsdb.proxy.new(b, 'lsdbus.test', '/', 'lsdbus.test.testintf0')

local s1,s2,s3,s4,s5,s6

while true do
   s1 = tst:call_async('pow', pow_cb, cnt)
   s2 = tst:call_async('concat', concat_cb, 'a', 'b', tostring(cnt))
   s3 = tst:call_async('thunk', function () u.pp("thunk cb") end)
   s4 = tst:call_async('twoin', function (_, ...) u.pp("twoin cb", ...) end, cnt, {"a","b"})
   s5 = tst:call_async('twoout', function (_, ...) u.pp("twoout cb", ...) end)
   s6 = tst:call_async('Fail', fail_cb)
   while b:run(100) ~= 0 do end
end
