local u = require("utils")
local lsdb = require("lsdbus")
local proxy = require("lsdbus_proxy")

local b = lsdb.open('user')

local tst=proxy:new(b, 'lsdbus.test', '/', 'lsdbus.test.testintf0')

local cnt = -1
while cnt ~= 0 do
   u.pp(cnt, tst('pow', cnt))
   u.pp(cnt, tst('concat', "foo", "bar"))
   u.pp(cnt, tst('getarray', 10))
   u.pp(cnt, tst('getdict', 10))
   u.pp(cnt, tst('getarray', 1000))
   u.pp(cnt, tst('getdict', 1000))
   u.pp(cnt, tst('thunk'))
   u.pp(cnt, tst('twoin', 333, { a="yes", b="maybe" }))
   u.pp(cnt, tst('twoout'))

   u.pp(cnt, "reading Bar: ", tst.Bar)
   tst.Bar=cnt%255
   u.pp(cnt, "setting Bar: ", tst.Bar)
   u.pp(cnt, "reading Bar: ", tst.Bar)
   u.pp(cnt, tst.Date)
   tst.Wronly="Wonly "..tostring(cnt)
   cnt=cnt-1
   u.pp(cnt, tst('Raise'))
end
