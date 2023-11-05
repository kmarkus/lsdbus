local u = require("utils")
local lsdb = require("lsdbus")

local function exit(b, sig)
   print("exiting on", sig)
   b:exit_loop()
end

local function nothrow(func, log)
   return function(...)
      local res, ret = pcall(func, ...)
      if not res then log(ret); return 0 end
      return ret
   end
end

local b = lsdb.open('user')
b:add_signal(lsdb.SIGINT, exit)
--b:match_signal(nil, nil, nil, nil, nothrow(function(_, ...) u.pp(...) end, print))
b:match_signal(nil, nil, nil, nil, function(_, ...) u.pp(...); error("oh no") end, print)
b:loop()
