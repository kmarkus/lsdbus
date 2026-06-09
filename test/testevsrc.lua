
local lu=require("luaunit")
local lsdb = require("lsdbus")
local have_socket, socket = pcall(require, "posix.sys.socket")
local have_unistd, unistd = pcall(require, "posix.unistd")

local MEM_USAGE_MARGIN_KB = 64

local testconf = debug.getregistry()['lsdbus.testconfig']

local b = lsdb.open(testconf.bus)

local TestEvSrc = {}

local function need_posix()
   if not have_socket or not have_unistd then
      lu.skip("no luaposix")
   end
end

function TestEvSrc:TestNoLeak()
   need_posix()

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

function TestEvSrc:TestGC()
   need_posix()
   collectgarbage()
   local mem1 = collectgarbage('count')

   for i=1,1000 do
      local x,y = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM, 0)
      assert(x, string.format("%d: %s", i, y))
      b:add_io(x, lsdb.EPOLLIN, function() end)
      unistd.close(x)
      unistd.close(y)
   end

   collectgarbage()
   collectgarbage()

   local mem2 = collectgarbage('count') - MEM_USAGE_MARGIN_KB

   lu.assert_false(mem2>mem1, string.format("mem2 > mem1 (%s>%s)", mem2, mem1))
end

function TestEvSrc:TestClose()
   need_posix()
   local code = [[
      local b, x, lsdb = ...
      local evsrc <close> = b:add_io(x, lsdb.EPOLLIN, function() end)
   ]]
   local f, err = load(code)
   if not f then lu.skip("requires Lua 5.4+: " .. tostring(err)); return end

   local x,y = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM, 0)
   assert(x)
   f(b, x, lsdb)
   unistd.close(x)
   unistd.close(y)
end

--- regression: a periodic callback unref'ing its own event source
--- used to crash (sd-event aborts when rearming the now-detached
--- source). it must instead stop cleanly.
function TestEvSrc:TestUnrefInPeriodicCallback()
   local count = 0
   local evsrc
   evsrc = b:add_periodic(1000, 0, function()
      count = count + 1
      evsrc:unref()
   end)

   for _=1,100 do
      if count >= 1 then break end
      b:run(10*1000)
   end

   lu.assert_equals(count, 1)

   -- the source must be detached: further loop iterations must not
   -- fire the callback again
   for _=1,10 do b:run(10*1000) end
   lu.assert_equals(count, 1)
end

return TestEvSrc
