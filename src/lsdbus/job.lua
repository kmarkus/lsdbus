--- lsdbus.job: run long running work in slices via the event loop
--
-- A job wraps a function in a coroutine that is resumed periodically
-- by the event loop. The function must call coroutine.yield() between
-- slices of work. When it returns or raises an error, the job
-- automatically cleans up its event source. While running, the job is
-- kept alive by the event source, so no reference to it needs to be
-- held unless one wants to stop it early.

local Job = {}
Job.__index = Job

--- Start a new job
-- @param bus bus connection with an attached event loop
-- @param fn job function; must call coroutine.yield() between slices
-- @param period microseconds between resumes (default 1000)
-- @param errh optional error handler errh(err). If absent, errors are
--        re-raised into the event loop, which reports them to stderr.
-- @return job object
function Job.start(bus, fn, period, errh)
   local self = setmetatable({ _co = coroutine.create(fn), _errh = errh }, Job)
   self._evsrc = bus:add_periodic(period or 1000, 0, function() self:_step() end)
   return self
end

-- resume the job coroutine and clean up when it completes or fails
function Job:_step()
   local ok, err = coroutine.resume(self._co)
   if not ok or coroutine.status(self._co) == "dead" then
      self:stop()
      if not ok then
         if self._errh then self._errh(err) else error(err) end
      end
   end
end

--- Stop (or cancel) the job. Idempotent.
function Job:stop()
   if self._evsrc then
      self._evsrc:unref()
      self._evsrc = nil
   end
end

--- Return true while the job is running
function Job:running() return self._evsrc ~= nil end

return Job
