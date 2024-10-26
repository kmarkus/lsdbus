--
-- Small example of using add_io with input events
-- This is basically a tiny Lua version of evtest(1)
--
-- see https://www.kernel.org/doc/html/latest/input/event-codes.html
--

local lsdb = require('lsdbus.core')
local unistd = require('posix.unistd')
local fcntl = require("posix.fcntl")

local struct_input_event_fmt = "=lI4HHI4"
local struct_input_event_size = string.packsize(struct_input_event_fmt)

--- read a struct input_event
-- returns tv_sec, tv_usec, ev_type, ev_code, value
local function read_input_event(data)
   assert(#data == struct_input_event_size)
   return string.unpack(struct_input_event_fmt, data)
end

local function handle_input(b, fd, revents)
   while true do
      local data = unistd.read(fd, struct_input_event_size)

      if data==nil or #data ~= struct_input_event_size then
	 break
      end

      local sec, usec, typ, code, val = read_input_event(data)
      print(sec, usec, typ, code, val)
   end
end

if arg[1] == nil then
   print(string.format("usage: %s /dev/input/eventX", arg[0]))
   os.exit(1)
end

local dev = arg[1]
local b = lsdb.open()
local fd = assert(fcntl.open(dev, fcntl.O_RDONLY|fcntl.O_NONBLOCK))

b:add_io(fd, lsdb.EPOLLIN, handle_input)
b:add_signal(lsdb.SIGINT, function() print("bye"); b:exit_loop() end)

b:loop()
