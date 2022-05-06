--
-- Small example of using add_io with inotify.
--

local lsdb = require 'lsdbus'
local inotify = require 'inotify'
local u = require 'utils'

local b = lsdb.open()
local handle = inotify.init()
local wd = handle:addwatch('/tmp/', inotify.IN_ALL_EVENTS)

b:add_io(handle:getfd(), lsdb.EPOLLIN, function (...) u.pp(..., handle:read()) end)

b:loop()
