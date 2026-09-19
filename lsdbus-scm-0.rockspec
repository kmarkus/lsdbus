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
   "compat53 >= 0.5",    -- only used for lua < 5.3
   "luaexpat >= 1.3.0",  -- default XML backend, unused when built USE_MXML=ON
}

external_dependencies = {
   LIBSYSTEMD = { header = "systemd/sd-bus.h" }
}

-- The XML backend defaults to luaexpat here, as that avoids a libmxml build
-- dependency. To build the mxml backend instead (libmxml-dev required):
--
--   luarocks install --dev lsdbus USE_MXML=ON USE_EXPAT=OFF
--
build = {
   type = "cmake",
   variables = {
      CMAKE_INSTALL_PREFIX = "$(PREFIX)",
      CONFIG_LUADIR = "$(LUADIR)",
      CONFIG_LIBDIR = "$(LIBDIR)",
      CONFIG_LUA_BIN = "$(LUA)",
      CONFIG_LUA_INCDIR = "$(LUA_INCDIR)",
      USE_MXML = "$(USE_MXML)",
      USE_EXPAT = "$(USE_EXPAT)",
   },
}
