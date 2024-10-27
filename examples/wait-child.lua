-- tiny example to illustrate use of child pid event source

local lsdb = require("lsdbus.core")
local unistd = require("posix.unistd")
local utils = require("utils")

local si_code_tostr = {
   [lsdb.CLD_EXITED] = "CLD_EXITED",
   [lsdb.CLD_KILLED] = "CLD_KILLED",
   [lsdb.CLD_DUMPED] = "CLD_DUMPED",
   [lsdb.CLD_STOPPED] = "CLD_STOPPED",
   [lsdb.CLD_TRAPPED] = "CLD_TRAPPED",
   [lsdb.CLD_CONTINUED] = "CLD_CONTINUED",
}

local function callback(b, si)
   utils.pp(b, si, si_code_tostr[si.code])
end

local function do_fork()
   local pid = unistd.fork()
   if pid == 0 then
      unistd.exec("/usr/bin/sleep", {30})
      unistd._exit(1)
   else
      return pid
   end
end

local b = lsdb.open()
local pid = do_fork()

local info = utils.expand([[
Child process with pid $PID exit in 60s
Send it signals like

$ kill -SIGSTOP $PID
$ kill -SIGCONT $PID
$ kill -SIGKILL $PID

to test the wait callback.
]], {PID=pid})

print(info)

b:add_child(pid, lsdb.WEXITED|lsdb.WSTOPPED|lsdb.WCONTINUED, callback)

b:loop()
