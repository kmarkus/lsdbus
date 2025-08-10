cmake_minimum_required(VERSION 3.20)

project(sdbus-lua VERSION 0.0.1 LANGUAGES C)
set(CMAKE_C_STANDARD 11)

include(GNUInstallDirs)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SYSTEMD REQUIRED libsystemd>=242)
pkg_check_modules(MXML REQUIRED mxml)

set(CONFIG_LUA_VER "" CACHE STRING "build for exact Lua version")

if(NOT "${CONFIG_LUA_VER}" STREQUAL "")
  pkg_search_module(LUA "lua${CONFIG_LUA_VER}" REQUIRED)
else()
  pkg_search_module(LUA lua5.4 lua5.3 luajit lua5.2 lua5.1 lua REQUIRED)
endif()

if ("${LUA_MODULE_NAME}" STREQUAL "luajit")
  pkg_get_variable(LUA_VER ${LUA_MODULE_NAME} abiver)
else()
  # remove minor version (meta-oe pc file has no major_version)
  pkg_get_variable(LUA_VER ${LUA_MODULE_NAME} version)
  string(REGEX MATCH "^([0-9]+\\.[0-9]+)" LUA_VER ${LUA_VERSION})
endif()

message(STATUS "Found ${LUA_MODULE_NAME} (${LUA_VER})")

if( "${LUA_VER}" STREQUAL "5.1" OR "${LUA_VER}" STREQUAL "5.2" )
  find_file(COMPAT53 compat-5.3.h PATH_SUFFIXES "lua${LUA_VER}")

  if(NOT COMPAT53)
    message(FATAL_ERROR "failed to find compat-5.3.h for lua${LUA_VER}, please install lua-compat53-dev")
  else()
    message(STATUS "lua-compat53 found")
  endif()
  cmake_path(GET COMPAT53 PARENT_PATH COMPAT53_DIR)
endif()

set(LSDBUS_SRCS
  src/errparse.c
  src/evl.c
  src/introspect.c
  src/lsdbus.c
  src/message.c
  src/vtab.c
)

set(CONFIG_LUADIR "${CMAKE_INSTALL_PREFIX}/share/lua/${LUA_VER}" CACHE STRING "lua script dir")
set(CONFIG_LIBDIR "${CMAKE_INSTALL_PREFIX}/lib/lua/${LUA_VER}" CACHE STRING "lua lib dir")

set(LSDBUS_INST_DIR
  ${CONFIG_LIBDIR}/lsdbus/)

add_library(core SHARED ${LSDBUS_SRCS})
target_compile_options(core PRIVATE -Wall -Wextra)
target_compile_definitions(core PRIVATE LIBSYSTEMD_VERSION=${SYSTEMD_VERSION})
target_include_directories(core PRIVATE ${LUA_INCLUDE_DIRS} ${COMPAT53_DIR})
target_link_libraries(core ${SYSTEMD_LIBRARIES} ${MXML_LIBRARIES} )
set_target_properties(core PROPERTIES PREFIX "")
install(TARGETS core LIBRARY DESTINATION ${LSDBUS_INST_DIR})

install(FILES
  src/lsdbus/init.lua
  src/lsdbus/proxy.lua
  src/lsdbus/server.lua
  src/lsdbus/common.lua
  src/lsdbus/error.lua
  DESTINATION ${CONFIG_LUADIR}/lsdbus/
  )

install(PROGRAMS
  tools/lsdb-call
  tools/lsdb-emit
  tools/lsdb-info
  tools/lsdb-mon
  tools/lsdb-prop
  DESTINATION ${CMAKE_INSTALL_BINDIR})
