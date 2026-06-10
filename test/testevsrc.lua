
local lu=require("luaunit")
local lsdb = require("lsdbus")
local have_socket, socket = pcall(require, "posix.sys.socket")
local have_unistd, unistd = pcall(require, "posix.unistd")
local have_ptime, ptime = pcall(require, "posix.time")

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

--- regression: a period of 0 used to hang the process in the timer
--- rearm loop
function TestEvSrc:TestPeriodicZeroPeriod()
   lu.assertErrorMsgContains("period must be > 0",
      function() b:add_periodic(0, 0, function() end) end)
end

--- regression: an explicit nil enabled arg used to disable the
--- source, unlike omitting the argument
function TestEvSrc:TestPeriodicNilEnabled()
   local evsrc = b:add_periodic(1000, 0, function() end, nil)
   lu.assert_equals(evsrc:get_enabled(), lsdb.SD_EVENT_ON)
   evsrc:unref()
end

function TestEvSrc:TestAddSignal()
   local evsrc = b:add_signal(lsdb.SIGUSR2, function() end)
   lu.assert_str_contains(tostring(evsrc), "unix_signal")
   lu.assert_equals(evsrc:get_enabled(), lsdb.SD_EVENT_ON)
   evsrc:unref()
end

function TestEvSrc:TestAddChild()
   if not have_unistd then lu.skip("no luaposix") end

   local pid = unistd.fork()
   lu.assert_not_nil(pid)

   if pid == 0 then
      -- child: sleep briefly so the parent can register the source,
      -- then exit with a known status
      if have_ptime then
	 ptime.nanosleep({tv_sec=0, tv_nsec=100*1000*1000})
      else
	 unistd.sleep(1)
      end
      unistd._exit(7)
   end

   local si
   local evsrc = b:add_child(pid, lsdb.WEXITED, function(_, s) si = s end)

   for _=1,300 do
      if si then break end
      b:run(10*1000)
   end

   lu.assert_not_nil(si)
   lu.assert_equals(si.pid, pid)
   lu.assert_equals(si.status, 7)
   lu.assert_equals(si.code, lsdb.CLD_EXITED)
   evsrc:unref()
end

return TestEvSrc
