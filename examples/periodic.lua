local lsdb = require("lsdbus")

local evsrc
local enabled = 1
local b = lsdb.open('user')

local function toggle()
   if enabled==1 then enabled=0 else enabled=1 end
   print("enabled:", enabled)
   evsrc:set_enabled(enabled)
end

local function loop() print(os.date()) end
local function exit(sig) b:exit_loop() end

b:add_signal("SIGINT", exit)
b:add_signal("SIGUSR1", toggle)
evsrc = b:add_periodic(1000^2, 0, loop)
b:loop()

print("exited loop, shutting down")
