--
-- periodic: periodic timer event source with enable/disable toggle
--
-- Demonstrates: add_periodic, enabling/disabling an event source at
-- runtime via SIGUSR1, clean exit via SIGINT.
--
--   kill -SIGUSR1 <pid>   # toggle timer on/off
--   kill -SIGINT  <pid>   # exit

local lsdb = require("lsdbus")

local evsrc

local function toggle()
   local on = evsrc:get_enabled() == lsdb.SD_EVENT_ON
   evsrc:set_enabled(on and lsdb.SD_EVENT_OFF or lsdb.SD_EVENT_ON)
   print("timer:", on and "disabled" or "enabled")
end

local b = lsdb.open()
local sig_int  = b:add_signal(lsdb.SIGINT,  function() b:exit_loop() end)
local sig_usr1 = b:add_signal(lsdb.SIGUSR1, toggle)
evsrc = b:add_periodic(1*1000^2, 0, function() print(os.date()) end)
b:loop()
