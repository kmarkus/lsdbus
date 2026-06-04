--- tests for lsdbus.job

local lu = require("luaunit")
local lsdb = require("lsdbus")
local job = lsdb.job

local testconf = debug.getregistry()['lsdbus.testconfig']

local TestJob = {}

local b

function TestJob:setup()
   b = lsdb.open(testconf.bus)
end

function TestJob:teardown()
   b = nil
end

function TestJob:TestRunsToCompletion()
   local steps = {}

   local j = job.start(b, function()
      for i=1,5 do
	 steps[#steps+1] = i
	 coroutine.yield()
      end
   end, 100)

   lu.assert_true(j:running())

   for _=1,100 do
      if not j:running() then break end
      b:run(10*1000)
   end

   lu.assert_false(j:running())
   lu.assert_equals(steps, {1,2,3,4,5})
end

--- a running job must survive GC without external refs and become
--- collectable once completed
function TestJob:TestSelfCleanup()
   local done = false
   local weak = setmetatable({}, {__mode='v'})

   weak.j = job.start(b, function()
      coroutine.yield()
      done = true
   end, 100)

   collectgarbage(); collectgarbage()
   lu.assert_not_nil(weak.j, "running job was collected")

   for _=1,100 do
      if done then break end
      b:run(10*1000)
   end

   lu.assert_true(done)

   collectgarbage(); collectgarbage()
   lu.assert_nil(weak.j, "completed job was not collected")
end

function TestJob:TestStop()
   local count = 0

   local j = job.start(b, function()
      while true do
	 count = count + 1
	 coroutine.yield()
      end
   end, 100)

   for _=1,100 do
      if count >= 3 then break end
      b:run(10*1000)
   end

   lu.assert_true(count >= 3)

   j:stop()
   lu.assert_false(j:running())

   local count_stopped = count
   for _=1,10 do b:run(10*1000) end
   lu.assert_equals(count, count_stopped)

   j:stop() -- idempotent
end

function TestJob:TestErrorHandler()
   local err

   local j = job.start(b, function()
      coroutine.yield()
      error("boom")
   end, 100, function(e) err = e end)

   for _=1,100 do
      if err then break end
      b:run(10*1000)
   end

   lu.assert_str_contains(tostring(err), "boom")
   lu.assert_false(j:running())
end

-- Read VmRSS in kB from /proc/self/status (Linux only), returns nil if unavailable
local function get_rss_kb()
   local f = io.open("/proc/self/status", "r")
   if not f then return nil end
   local rss
   for line in f:lines() do
      rss = line:match("^VmRSS:%s+(%d+)")
      if rss then break end
   end
   f:close()
   return tonumber(rss)
end

local function count_evsrcs()
   local n = 0
   for _ in pairs(debug.getregistry()['lsdbus.evsrc_table']) do n = n + 1 end
   return n
end

-- start num jobs of a few slices each and run the loop until all completed
local function run_jobs(num)
   local ndone = 0

   for _=1,num do
      job.start(b, function()
	 for _=1,3 do coroutine.yield() end
	 ndone = ndone + 1
      end, 100)
   end

   for _=1,100*num do
      if ndone == num then break end
      b:run(1000)
   end

   lu.assert_equals(ndone, num)
end

function TestJob:TestNoLeak()
   local MEM_MARGIN_KB = 64
   local N = 500

   -- warm-up with two full batches to pre-expand malloc arena and
   -- (on LuaJIT) to get hot paths compiled before measuring
   run_jobs(N)
   run_jobs(N)
   collectgarbage(); collectgarbage()

   local nevsrc1 = count_evsrcs()
   local rss1 = get_rss_kb()
   local lua1 = collectgarbage('count')

   run_jobs(N)

   collectgarbage(); collectgarbage()

   local nevsrc2 = count_evsrcs()
   local rss2 = get_rss_kb()
   local lua2 = collectgarbage('count')

   -- all job event sources must have been cleaned up
   lu.assert_equals(nevsrc2, nevsrc1)

   -- Lua heap should not have grown appreciably
   lu.assert_false(lua2 - lua1 > MEM_MARGIN_KB,
      string.format("Lua heap grew by %.1f kB after %d jobs", lua2 - lua1, N))

   -- C heap (RSS) should not have grown appreciably
   if rss1 and rss2 then
      lu.assert_false(rss2 - rss1 > MEM_MARGIN_KB,
	 string.format("RSS grew by %d kB after %d jobs (possible C leak)", rss2 - rss1, N))
   end
end

--- start a job on the peer-testserver and collect its progress signals
function TestJob:TestPeerJob()
   local intf = 'lsdbus.test.testintf0'
   local path = '/1'
   local progress, done = {}, false
   local slots = {}

   slots[#slots+1] = b:match_signal(nil, path, intf, 'JobProgress',
      function(_,_,_,_,_,step) progress[#progress+1] = step end)

   slots[#slots+1] = b:match_signal(nil, path, intf, 'JobDone',
      function() done = true end)

   local p = lsdb.proxy.new(b, 'lsdbus.test', path, intf)
   p('StartJob', 5)

   for _=1,20 do
      if done then break end
      b:run(100*1000)
   end

   lu.assert_true(done, "no JobDone signal received")
   lu.assert_equals(progress, {1,2,3,4,5})

   for _,s in ipairs(slots) do s:unref() end
end

return TestJob
