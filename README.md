# lsdbus

lsdbus is a simple to use D-Bus binding for Lua based on the sd-bus
and sd-event APIs.

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Installing](#installing)
- [Quickstart](#quickstart)
- [Usage](#usage)
    - [Bus connection](#bus-connection)
    - [Type mapping](#type-mapping)
        - [Testmsg](#testmsg)
    - [Client API](#client-api)
        - [lsdb.proxy](#lsdbproxy)
        - [plumbing API](#plumbing-api)
        - [Emitting signals](#emitting-signals)
    - [Server API](#server-api)
        - [Event loop](#event-loop)
        - [Registering Interfaces: Properties, Methods and Signal](#registering-interfaces-properties-methods-and-signal)
        - [D-Bus signal matching and callbacks](#d-bus-signal-matching-and-callbacks)
        - [Periodic callbacks](#periodic-callbacks)
        - [Unix Signal callbacks](#unix-signal-callbacks)
        - [Returning D-Bus errors](#returning-d-bus-errors)
- [API](#api)
    - [Functions](#functions)
    - [Bus connection object](#bus-connection-object)
    - [lsdbus.proxy](#lsdbusproxy)
    - [lsdbus.server](#lsdbusserver)
    - [slots](#slots)
    - [event sources](#event-sources)
- [Internals](#internals)
    - [Introspection](#introspection)
- [License](#license)
- [References](#references)

<!-- markdown-toc end -->


## Installing

First, ensure that the correct packages are installed. For example:

```sh
$ sudo apt-get install cmake lua5.3 liblua5.3-dev libsystemd-dev libmxml-dev
```

To run the tests, install `lua-unit` or install it directly from here
[2]. Then build via CMake:

```sh
$ cd lsdbus
$ mkdir build && cd build
$ cmake .. && make
...
$ sudo make install
```

## Quickstart

**Server**

```sh
$ lua -l lsdbus
Lua 5.3.6  Copyright (C) 1994-2020 Lua.org, PUC-Rio
> b=lsdbus.open()
> b:request_name("lsdbus.test")
> intf = { name="lsdbus.testif", methods={ Hello={ handler=function() print("hi lsdbus!") end }}}
> s = lsdbus.server:new(b, "/", intf)
> b:loop()
```

**Client** (open a second terminal)

```
$ lua -l lsdbus
Lua 5.3.6  Copyright (C) 1994-2020 Lua.org, PUC-Rio
> b = lsdbus.open()
> p = lsdbus.proxy:new(b, "lsdbus.test", '/', "lsdbus.testif")
> p
srv: lsdbus.test, obj: /, intf: lsdbus.testif
Methods:
  Hello () -> 
> p('Hello')
> p('Hello')
```

## Usage

### Bus connection

Before doing anything, it is necessary to connect to a bus:

```lua
lsdb = require("lsdbus")
b = lsdb.open()
```

### Type mapping

#### Testmsg

To faciliate testing message conversion, lsdbus provides the `testmsg`
function, that accepts a D-Bus message specifier (see
`sd_bus_message_append(3)` and a value, creates a D-Bus message from
it and converts it back to Lua (the example below uses the small
`uutils` [2] library for printing tables):

```lua
> lsdb = require("lsdbus")
> u = require("utils")
> b = lsdb.open()
> u.pp(b:testmsg('u', 33))
33
> u.pp(b:testmsg('ai', {1,2,3,4}))
{1,2,3,4}
> u.pp(b:testmsg('a{s(is)}', { one = {1, 'this is one'}, two = {2, 'this is two'} }))
{one={1,"this is one"},two={2,"this is two"}}
> u.pp(b:testmsg('a{sv}', { foo={'s', "nirk"}, bar={'d', 2.718}, dunk={'b', false}}))
{foo="nirk",dunk=false,bar=2.718}
```

**Type conversions**

| D-Bus Type      | D-Bus specifier                   | Lua                  | Example Lua to D-Bus msg...  | ...and back to Lua  |
|-----------------|-----------------------------------|----------------------|------------------------------|---------------------|
| boolean         | `b`                               | `boolean`            | `'b', true`                  | `true`              |
| integers        | `y`, `n`, `q`, `i`, `u`, `x`, `t` | `number` (integer)   | `'i', 42`                    | `42`                |
| floating-point  | `d`                               | `number` (double)    | `'d', 3.14`                  | `3.14`              |
| file descriptor | `h`                               | `number`             |                              |                     |
| string          | `s`                               | `string`             | `'s', "foo"`                 | `"foo"`             |
| signature       | `g`                               | `string`             | `'g', "a{sv}"`               | `"a{sv}"`           |
| object path     | `o`                               | `string`             | `'o', "/a/b/c"`              | `"/a/b/c"`          |
| variant         | `v`                               | `{SPECIFIER, VALUE}` | `'v', {'i', 33 }`            | `33`                |
| array           | `a`                               | `table` (array part) | `'ai', {1,2,3,9}`            | `{1,2,3,9}`         |
| struct          | `(...)`                           | `table` (array part) | `'(ibs)', {3, false, "hey"}` | `{3, false, "hey"}` |
| dictionary      | `a{...}`                          | `table` (dict part)  | `'a{si}', {a=1, b=2}`        | `{a=1, b=2}`        |

*Notes:*

- More examples can be found in the unit tests: `test/message.lua`
- *Variant* is the only type whose conversion is asymmetrical,
  i.e. the input arguments are not equal the result. This is because
  the variant is unpacked automatically.

### Client API

There are two client APIs: the high level `lsdbus.proxy` API uses
introspection to create a proxy object, that can be used to
conveniently call methods or get/set properties. The plumbing API
allows the same, however more arguments (destination, path, interface,
member, typestring and args) need to be provided.

#### lsdb.proxy

**Example**

```lua
> lsdb = require("lsdbus")
> b = lsdb.open("system")
> td = lsdb.proxy:new(b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1')
> print(td)
srv: org.freedesktop.timedate1, obj: /org/freedesktop/timedate1, intf: org.freedesktop.timedate1
Methods:
  SetLocalRTC (bbb) ->
  SetTime (xbb) ->
  SetTimezone (sb) ->
  SetNTP (bb) ->
  ListTimezones () -> as
Properties:
  Timezone: s, read
  LocalRTC: b, read
  NTP: b, read
  TimeUSec: t, read
  NTPSynchronized: b, read
  RTCTimeUSec: t, read
  CanNTP: b, read
Signals:
```

**Properties** can be accessed by indexing the proxy:

```lua
> td.Timezone
Pacific/Tahiti
```

**Methods** can called by "calling" the proxy and providing the Method
name as the first argument:

```lua
> td('ListTimezones')
```

Unlike with the low-level `bus:call`, no D-Bus types need to be
provided.

#### plumbing API

**Syntax**

```lua
ret, res0, ... = bus:call(dest, path, intf, member, typestr, arg0...)
```

in case of success `ret` is `true` and `res0`, `res1`, ... are the
return values of the call.

if case of failure `ret` is `false` and `res0` is a table of the form
`{ error, message }`.


**Example**

```lua
lsdb = require("lsdbus")
b = lsdb.open('default_system')
u = require("utils")

-- calling a valid method
u.pp(b:call('org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1', 'ListTimezones')})
true, {"Africa/Abidjan","Africa/Accra","Africa/Addis_Ababa", ...

-- calling an invalid method
u.pp(b:call('org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1', 'NoMethod'))
false, {"org.freedesktop.DBus.Error.UnknownMethod","Unknown method NoMethod or interface org.freedesktop.timedate1."}
```

#### Emitting signals

```lua
b:emit_signal(PATH, INTERFACE, MEMBER, TYPESTR, ARG0...)
```

**Example**

```lua
b:emit_signal("/foo", "lsdbus.foo.bar0", "Alarm", "ia{ss}", 999, {x="one", y="two"})
```

### Server API

#### Event loop

The event loop can be entered and exited by calling

```lua
b:loop()
-- and
b:exit_loop()
```

respectively. Alternatively,

```
b:run(usec)
```

allows running the loop for a limited time (see `sd_event_loop(3)`,
`sd_event_run(3)` and `sd_event_exit(3)`.)

Any callback can use the method `b:context()` to retrieve additional
information which depending on the callback type may include

- `interface`
- `path`
- `member`
- `sender`
- `destination`

(these are retrieved using `sd_bus_get_current_message(3)` and the
respective `sd_bus_message_get_*(3)` functions).

#### Registering Interfaces: Properties, Methods and Signal

Server object callbacks can be registered with
`lsdbus.server:new`. The interface uses the same Lua representation of
the D-Bus interface XML (see below) decorated with callback functions:

```lua
local interface_table = {
   name="foo.bar.interface0",
   methods = {
      Method1 = {
             { direction=['in'|'out'], name=ARG0NAME, type=TYPESTR },
               ...
              handler=function(in0, in1...) return out0, out1... end
      }
   },
   properties  = {
      Property1 = {
         access = ['read'|'readwrite'|'write'],
         type = TYPESTR,
         get = function() return VALUE end
         set = function(value)
                  store(value)
                  b:emit_properties_changed(PATH, INTF, Property1)
                end
      }
   },
   signals = {
      Signal1 = {
             { name=ARG0NAME, type=TYPESTR },
              ...
      }
   },
}

local b = lsdb.open('user')
b:request_name("well.known.name"))
srv = lsdbs.server:new(b, PATH, interface_table)
b:loop()
```

Additionally, `lsdbus.server` objects allow emitting the specified
`signals` conveniently via `srv:emit('Signal1', arg0, ...)` instead of
the longer `bus:emit_signal(...)`.

For further information, take a look at the minimal example
`examples/tiny-server.lua` and the more extensive one
`examples/server.lua`.

#### D-Bus signal matching and callbacks

```lua
function callback(sender, path, interface, member, arg0...)
  -- do something
end

slot = bus:match_signal(sender, path, interface, member, callback)
slot = bus:match(match_expr, callback)
```

These correspond to `sd_bus_match_signal(3)` and `sd_bus_add_match(3)`
respectively.

**Example**: dump all signals on the system bus:

```lua
local u = require("utils")
local lsdb = require("lsdbus")
local b = lsdb.open('system')
b:match_signal(nil, nil, nil, nil, u.pp)
b:loop()
```

#### Periodic callbacks

```lua
local function callback()
  -- do something
end

evsrc = b:add_periodic(period, accuracy, callback)
```

The `period` and `accuracy` (both in microseconds) correspond to the
same parameters in `sd_event_add_time(3)`.

The returned `event_src` object supports a method `set_enable(int)`
that allows enabling and disabling the event source.

See `examples/periodic.lua` for an example.

#### Unix Signal callbacks

```
local function callback(signal)
  print("received signal " .. signal)
end
b:add_signal("SIGINT", callback)
```

Currently supported are `SIGINT`, `SIGTERM`, `SIGUSR1`, `SIGUSR2`.

#### Returning D-Bus errors

D-Bus errors can be returned by raising a Lua error of the following
form

```Lua
error("org.freedesktop.DBus.Error.InvalidArgs|Something is wrong")
```

## API

### Functions

| Functions             | Description                                      |
|-----------------------|--------------------------------------------------|
| `lsdbus.open(NAME)`   | open bus connection                              |
| `lsdbus.xml_fromfile` | parse a D-Bus XML file and return as Lua table   |
| `lsdbus.xml_fromstr`  | parse a D-Bus XML string and return as Lua table |

### Bus connection object

| Methods                                                                       | Description                                  |
|-------------------------------------------------------------------------------|----------------------------------------------|
| `bus:request_name(NAME)`                                                      | see `sd_bus_request_name(3)`                 |
| `slot = bus:match_signal(sender, path, intf, member, callback)`               | see `sd_bus_add_match(3)`                    |
| `slot = bus:match(match_expr, handler)`                                       | see `sd_bus_add_match(3)`                    |
| `bus:emit_properties_changed(propA, propB...)`                                | see `sd_bus_emit_properties_changed(3)`      |
| `bus:emit_signal(path, intf, member, typestr, args...)`                       | see `sd_bus_emit_signal(3)`                  |
| `evsrc = bus:add_signal(SIGNAL)`                                              | see `sd_event_add_signal(3)`                 |
| `evsrc = bus:add_periodic(period, accuracy, callback)`                        | see `sd_event_add_time_relative(3)`          |
| `bus:loop()`                                                                  | see `sd_event_loop(3)`                       |
| `bus:run(usec)`                                                               | see `sd_event_run(3)`                        |
| `bus:exit_loop()`                                                             | see `sd_event_exit(3)`                       |
| `table = bus:context()`                                                       | see `sd_bus_message_set_destination(3)` etc. |
| `number = bus:get_method_call_timeout`                                        | see `sd_bus_get_method_call_timeout(3)`      |
| `bus:set_method_call_timeout`                                                 | see `sd_bus_set_method_call_timeout(3)`      |
| `res = bus:testmsg(typestr, args...)`                                         | test Lua->D-Bus->Lua message roundtrip       |
| `ret, res... = bus:call(dest, path, intf, member, typestr, args...)`          | plumbing, prefer lsdbus.proxy                |
| `slot = bus:call_async(callback, dest, path, intf, member, typestr, args...)` | plumbping async method invocation            |
| `bus:add_object_vtable`                                                       | plumbing, use lsdbus.server instead          |


*Notes:*

- `lsdb.open` accepts an optional string parameter to indicate which
  bus to open: `default`, `system`, `user`, `default_system`,
  `default_user` correspond function as described in
  `sd_bus_default(3)`.  If not given, default is `'default'`

- `evsrc` (event source) objects are not garbage collected but can be
  used to explicitely remove the respective interface or callbacks
  (see below).

- bus objects are garbage collected

### lsdbus.proxy

| Method                                         | Description                                           |
|------------------------------------------------|-------------------------------------------------------|
| `prxy = lsdbus.proxy:new(bus, srv, obj, intf)` | constructor                                           |
| `prxy(method, arg0, ...)`                      | call a D-Bus method                                   |
| `prxy:call(method, arg0, ...)`                 | same as above, long form                              |
| `prxy:HasMethod(method)`                       | check if prxy has a method with the given name        |
| `prxy:callt(method, ARGTAB)`                   | call a method with a table of arguments               |
| `prxy:call_async(method, callback ARGTAB)`     | call a method asynchronously (returns slot)           |
| `prxy:Get(name)`                               | get a properties value                                |
| `prxy.name`                                    | short form, same as previous                          |
| `prxy:Set(name, value)`                        | set a property                                        |
| `prxy.name = value`                            | short form for setting a property to value            |
| `prxy:GetAll(filter)`                          | get all properties that match the optional filter     |
| `prxy:SetAll(t)`                               | set all properties from a table                       |
| `prxy:HasProperty(prop)`                       | check if prxy has a property of the given name        |
| `prxy:Ping`                                    | call the `Ping` method on `org.freedesktop.DBus.Peer` |
| `prxy:error(err, msg)`                         | error handler, override to customize behavior         |

*Notes*

- `callt` is a convenience method that can be used for methods with named
  arguments: `b:callt{argA=2, argB="that"}`.
- `GetAll` accepts a filter which can be either
  1. a string [`read`|`readwrite`|`write`] describing the access mode
  2. a filter function that accepts `(name, value, description)` and
  returns `true` or `false` depending on whether the value shall be
  included in the result or not.
- see *Internals* about how `lsdbus.proxy` works.

### lsdbus.server

| Method                                     | Description                                                |
|--------------------------------------------|------------------------------------------------------------|
| `srv = lsdbus.server:new(bus, path, intf)` | create a new obj with the given path and interface         |
| `emit(signal, args...)`                    | emit a signal that is defined in the servers interface     |
| `emitPropertiesChanged(signal...)`         | emit a PropertiesChanged signal for one or more properties |
| `emitAllPropertiesChanged(filter)`         | emit a PropertiesChanged signal for all properties         |
| `error("dbus.error.name\|message")`        | return a D-Bus error and message from a callback           |

*Notes*:

- The `emitAllPropertiesChanged(filter)` takes an optional filter
  function which accepts the property name and property table and
  returns true or false depending on whether the property shall be
  included in the `PropertiesChanged` signal not.
- garbage collected (will unref vtable slot and cleanup resources)

### slots

| Method    | Description                               |
|-----------|-------------------------------------------|
| `unref()` | remove slot. calls `sd_bus_slot_unref(3)` |

- slots are not garbage collected except for those returned by async
  calls.

### event sources

Corresponds to `sd_event_source`.

| Method                 | Description                                                             |
|------------------------|-------------------------------------------------------------------------|
| `set_enabled(enabled)` | `enabled`: 0=OFF, 1=ON, -1 =ONESHOT. see sd_event_source_set_enabled(3) |
| `unref()`              | remove event source. calls `sd_event_source_unref(3)`                   |

*Notes*

- Event sources are not garbage collected with the exeption of those
  returned by asynchronous calls.

## Internals

### Introspection

The fourth parameter of `lsdbus.proxy:new` is typically a string
interface name, whose XML is then retrieved using the standard D-Bus
introspection interfaces and converted to a Lua representation using
`lsdb.xml_fromstr(xml)`. It is available as `proxy.intf`.

However, if introspection is not available, this Lua interface table
can be manually specified and provided directly as the fourth
parameter instead of a string. This way, `lsdb.proxy` can be used also
without introspection.

**Example**

```lua
intf = {
      name = 'foo.bar.myintf1',

      methods = {
         Foo = {},
         Bar = {
            { name='x', type='s', direction='in' },
            { name='y', type='u', direction='out' }
         },
      },

      properties = {
         Flip = {  type='s', access='readwrite' },
         Flop = { type='a{ss}', access='readwrite' },
         Flup = { type='s', access='read' },
      }
}

prx = proxy:new(b, 'foo.bar.ick1', '/my/nice/obj', intf)
print(prx)
srv: foo.bar.ick1, obj: /my/nice/obj, intf: foo.bar.myintf1
Methods:
  Foo () ->
  Bar (s) -> u
Properties:
  Flup: s, read
  Flip: s, readwrite
  Flop: a{ss}, readwrite
Signals:
```

## License

LGPLv2. A portion of the lsdbus type conversion is based on code from
systemd.

## References

[1] https://github.com/bluebird75/luaunit.git  
[2] https://github.com/kmarkus/uutils.git  
