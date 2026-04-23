--
-- wait-child: monitor a child process with add_child
--
-- Demonstrates: fork/exec a child, use add_child to receive an event
-- when the child exits, stops, or continues (equivalent to waitpid
-- with SIGCHLD). The child runs "sleep 30"; send it signals to test.
--
--   kill -SIGSTOP <child-pid>
--   kill -SIGCONT <child-pid>
--   kill -SIGKILL <child-pid>

local lsdb = require("lsdbus.core")
local unistd = require("posix.unistd")

local si_code_tostr = {
   [lsdb.CLD_EXITED]    = "CLD_EXITED",
   [lsdb.CLD_KILLED]    = "CLD_KILLED",
   [lsdb.CLD_DUMPED]    = "CLD_DUMPED",
   [lsdb.CLD_STOPPED]   = "CLD_STOPPED",
   [lsdb.CLD_TRAPPED]   = "CLD_TRAPPED",
   [lsdb.CLD_CONTINUED] = "CLD_CONTINUED",
}

local b = lsdb.open()

local pid = unistd.fork()
if pid == 0 then
   unistd.exec("/usr/bin/sleep", {"30"})
   unistd._exit(1)
end

print(string.format("child pid=%d  (send SIGSTOP/SIGCONT/SIGKILL to test)", pid))

local sig   = b:add_signal(lsdb.SIGINT, function() b:exit_loop() end)
local child = b:add_child(pid, lsdb.WEXITED|lsdb.WSTOPPED|lsdb.WCONTINUED,
   function(_, si)
      print(string.format("child event: %s", si_code_tostr[si.code] or si.code))
   end)
b:loop()
