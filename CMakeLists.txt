cmake_minimum_required(VERSION 3.5)

project(sdbus-lua VERSION 0.0.1 LANGUAGES C)
set(CMAKE_C_STANDARD 11)

include(GNUInstallDirs)

find_package(Lua REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(SYSTEMD libsystemd>=236)
pkg_check_modules(MXML REQUIRED mxml)

if(${LUA_VERSION_STRING} VERSION_LESS "5.3")
  find_file(COMPAT53 compat-5.3.h PATHS ${LUA_INCLUDE_DIR} NO_DEFAULT_PATH)
  if(NOT COMPAT53)
    message(FATAL_ERROR "missing compat-5.3.h in ${LUA_INCLUDE_DIR}, please install lua-compat53-dev")
  else()
    message(STATUS "lua-compat53 found")
  endif()
endif()

set(LSDBUS_SRC_DIR ${CMAKE_SOURCE_DIR}/src/)

set(LSDBUS_SRCS
  ${LSDBUS_SRC_DIR}/lsdbus.c
  ${LSDBUS_SRC_DIR}/message.c
  ${LSDBUS_SRC_DIR}/introspect.c
  ${LSDBUS_SRC_DIR}/evl.c
  ${LSDBUS_SRC_DIR}/vtab.c
)

set(LSDBUS_INST_DIR
  ${CMAKE_INSTALL_PREFIX}/lib/lua/${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR}/)

add_library(lsdbus SHARED ${LSDBUS_SRCS})
target_compile_options(lsdbus PRIVATE -Wall -Wextra)
target_include_directories(lsdbus PRIVATE ${LUA_INCLUDE_DIR})
target_link_libraries(lsdbus ${LUA_LIBRARIES} ${SYSTEMD_LIBRARIES} ${MXML_LIBRARIES} )
set_target_properties(lsdbus PROPERTIES PREFIX "")
install(TARGETS lsdbus LIBRARY DESTINATION ${LSDBUS_INST_DIR})

install(FILES lua/lsdbus_proxy.lua DESTINATION
  ${CMAKE_INSTALL_PREFIX}/share/lua/${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR}/)
