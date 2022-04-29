local u = require("utils")
local lsdb = require("lsdbus")
local b = lsdb.open('user')

local function exit(sig)
   print("exiting on", sig)
   b:exit_loop()
end

local function safe(func, log)
   return function(...)
      local res, ret = pcall(func, ...)
      if not res then log(ret); return 1 end
      return ret
   end
end

b:add_signal("SIGINT", exit)
b:match_signal(nil, nil, nil, nil, safe(function() error("something failed") end, print))
b:loop()
