local lsdb = require("lsdbus")

local b = lsdb.open()

local function sigint_cb(bus, signal)
   print("received signal:", signal)
   b:exit_loop()
end

local function sigusr1_cb(bus, signal)
   print("received signal:", signal)
   error("reloading ... ")
   b:exit_loop()
end


local sig_int = b:add_signal(lsdb.SIGINT, sigint_cb)
local sig_usr1 = b:add_signal(lsdb.SIGUSR1, sigusr1_cb)
b:loop()
