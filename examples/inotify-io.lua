--
-- Small example of using add_io with inotify.
--

local lsdb = require 'lsdbus'
local inotify = require 'inotify'

if arg[1] == nil then
   print(string.format("usage: %s DIR", arg[0]))
   os.exit(1)
end

local b = lsdb.open()
local handle = inotify.init()
local wd = handle:addwatch(arg[1], inotify.IN_ALL_EVENTS)

local events = {
   ACCESS =        inotify.IN_ACCESS,
   ATTRIB =        inotify.IN_ATTRIB,
   CLOSE_WRITE =   inotify.IN_CLOSE_WRITE,
   CLOSE_NOWRITE = inotify.IN_CLOSE_NOWRITE,
   CREATE =        inotify.IN_CREATE,
   DELETE =        inotify.IN_DELETE,
   DELETE_SELF =   inotify.IN_DELETE_SELF,
   MODIFY =        inotify.IN_MODIFY,
   MOVE_SELF =     inotify.IN_MOVE_SELF,
   MOVED_FROM =    inotify.IN_MOVED_FROM,
   MOVED_TO =      inotify.IN_MOVED_TO,
   OPEN =          inotify.IN_OPEN,
}

local function mask_to_events(mask)
   local res = {}
   for k,v in pairs(events) do
      if (mask & v) ~= 0 then res[#res+1] = k end
   end
   return table.concat(res, ", ")
end


b:add_io(handle:getfd(), lsdb.EPOLLIN,
	 function ()
	    for _,e in ipairs(handle:read()) do
	       print(e.wd, e.cookie, e.name, mask_to_events(e.mask))
	    end
	 end
)

b:loop()
