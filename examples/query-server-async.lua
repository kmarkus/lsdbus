local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('user')

local tst=lsdb.proxy:new(b, 'lsdbus.test', '/', 'lsdbus.test.testintf0')

local cnt = 0
local pow_cb=nil

local function concat_cb(...)
   u.pp("callback", b:context(), ...)
   u.pp(tst:call_async('pow', pow_cb, cnt))
   cnt = cnt + 1

end

function pow_cb(...)
   u.pp("callback", b:context(), ...)
   u.pp(tst:call_async('concat', concat_cb, 'a', 'b'..tostring(cnt)))
end


u.pp(tst:call_async('pow', pow_cb, 0))


b:loop()
