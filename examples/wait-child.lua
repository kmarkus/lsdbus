-- tiny example to illustrate use of child pid event source
-- send different signals to the

local lsdb = require("lsdbus")
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
      print("child process has pid", unistd.getpid())
      unistd.exec("/usr/bin/sleep", {60})
      unistd._exit(1)
   else
      return pid
   end
end

local b = lsdb.open()
local pid = do_fork()

b:add_child(pid, lsdb.WEXITED|lsdb.WSTOPPED|lsdb.WCONTINUED, callback)

b:loop()
