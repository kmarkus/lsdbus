local u = require("utils")
local lsdb = require("lsdbus")

local function exit(b, sig)
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

local b = lsdb.open('user')
b:add_signal("SIGINT", exit)
b:match_signal(nil, nil, nil, nil, safe(function(b, ...) u.pp(...) end, print))
b:loop()
