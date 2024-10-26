
local lu=require("luaunit")
local lsdb = require("lsdbus")
local have_socket, socket = pcall(require, "posix.sys.socket")
local have_unistd, unistd = pcall(require, "posix.unistd")

local MEM_USAGE_MARGIN_KB = 64

local testconf = debug.getregistry()['lsdbus.testconfig']

local b = lsdb.open(testconf.bus)

local TestEvSrc = {}

function TestEvSrc:setUp()
   if not have_socket or not have_unistd then
      lu.skip("no luaposix")
   end
end

function TestEvSrc:TestNoLeak()

   collectgarbage()
   local mem1 = collectgarbage('count')

   for i=1,1000 do
      local x,y = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM, 0)
      assert(x, string.format("%d: %s", i, y))
      local evsrc = b:add_io(x, lsdb.EPOLLIN, function() print("readable", x) end)
      evsrc:unref()
      unistd.close(x)
      unistd.close(y)
   end

   collectgarbage()
   collectgarbage()

   local mem2 = collectgarbage('count') - MEM_USAGE_MARGIN_KB

   lu.assert_false(mem2>mem1, string.format("mem2 > mem1 (%s>%s)", mem2, mem1))
end

return TestEvSrc
