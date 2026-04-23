--
-- Tiny disk space storage space monitor
--

local conf = {
   { "/", warn_at_perc=75 },
}

local POLL_RATE_SEC = 3.5

local b
local lsdb = require 'lsdbus'
local statvfs = require "posix.sys.statvfs".statvfs
local u = require 'utils'


local function checkfs()
   local inf = statvfs()

end

local b = lsdb.open()

local periodic = b:add_periodic(POLL_RATE_SEC*1000^2, 0, checkfs)

b:loop()
