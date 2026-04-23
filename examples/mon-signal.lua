--
-- mon-signal: monitor and print all D-Bus signals on the user bus
--
-- Demonstrates: match_signal with a wildcard subscription (all senders,
-- paths, interfaces and members). Useful for debugging signal traffic.
--
--   lua mon-signal.lua

local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('user')
local sig   = b:add_signal(lsdb.SIGINT, function() b:exit_loop() end)
local match = b:match_signal(nil, nil, nil, nil, function(_, ...) u.pp(...) end)
b:loop()
