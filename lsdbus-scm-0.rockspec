package = "lsdbus"
version = "scm-0"

description = {
   summary = "Lua D-Bus bindings based on sd-bus and sd-event",
   detailed = [[
        lsdbus is a simple to use D-Bus binding for Lua based on the sd-bus and sd-event APIs.
   ]],
   homepage = "https://github.com/kmarkus/lsdbus",
   license = "LGPL-2.1"
}

source = {
   url = "git+https://github.com/kmarkus/lsdbus.git"
}

dependencies = {
   "lua >= 5.1",
   "compat53 >= 0.5", -- only for lua < 5.3
}

build = {
   type = "cmake"
}
