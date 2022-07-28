local u = require("utils")
local lsdb = require("lsdbus")

local tst
local cnt = 0
local pow_cb=nil

local function concat_cb(b, ...)
   u.pp("callback", b:context(), ...)
   u.pp(tst:call_async('pow', pow_cb, cnt))
   cnt = cnt + 1
end

function pow_cb(b, ...)
   u.pp("callback", b:context(), ...)
   u.pp(tst:call_async('concat', concat_cb, 'a', 'b'..tostring(cnt)))
end


local function fail_cb(b, ...)
   u.pp("fail_cb", b:context(), {...})
   u.pp(tst:call_async('FailWithDBusError', fail_cb))
end

local b = lsdb.open('user')
tst = lsdb.proxy:new(b, 'lsdbus.test', '/', 'lsdbus.test.testintf0')

u.pp(tst:call_async('pow', pow_cb, 0))
--u.pp(tst:call_async('Fail', fail_cb))
--u.pp(tst:call_async('FailWithDBusError', fail_cb))


b:loop()
