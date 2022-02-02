local u = require("utils")
local lsdb = require("lsdbus")
local b = lsdb.open('user')

local function exit(sig)
   print("exiting on", sig)
   b:exit_loop()
end

b:add_signal("SIGINT", exit)
b:match_signal(nil, nil, nil, nil, u.pp)
b:loop()
