cmake_minimum_required(VERSION 3.5)

project(sdbus-lua VERSION 0.0.1 LANGUAGES C)

include(GNUInstallDirs)

find_package(Lua REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(SYSTEMD libsystemd>=236)

message(STATUS "libs: ${SYSTEMD_LIBRARIES}")
message(STATUS "cflags: ${SYSTEMD_LDFLAGS}")

set(LSDBUS_SRC_DIR ${CMAKE_SOURCE_DIR}/src/)

set(LSDBUS_SRCS
  ${LSDBUS_SRC_DIR}/sdbus.c
)


set(LSDBUS_INST_DIR
  ${CMAKE_INSTALL_PREFIX}/lib/lua/${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR}/)

add_library(lsdbus SHARED ${LSDBUS_SRCS})
target_include_directories(lsdbus PRIVATE ${LUA_INCLUDE_DIR})
target_link_libraries(lsdbus ${LUA_LIBRARIES} ${SYSTEMD_LIBRARIES} )
set_target_properties(lsdbus PROPERTIES PREFIX "")
install(TARGETS lsdbus LIBRARY DESTINATION ${LUA_INST_DIR})
