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
        - [I/O event callback](#io-event-callback)
        - [Child pid callback](#child-pid-callback)
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
- [Tests](#tests)
- [License](#license)
- [FAQ](#faq)
    - [Error `System.Error.ENOTCONN: Transport endpoint is not connected`](#error-systemerrorenotconn-transport-endpoint-is-not-connected)
    - [`System.Error.ENOTCONN` after exiting loop](#systemerrorenotconn-after-exiting-loop)
- [ChangeLog](#changelog)
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

If you have multiple Lua versions installed, you can force the one to
be used by setting `CONFIG_LUA_VER` (or pass `-DCONFIG_LUA_VER=X` to
cmake) to one of `5.4`, `5.3`, `5.2`, `5.1` or `jit`.

## Quickstart

**Server**

```sh
$ lua -l lsdbus
Lua 5.3.6  Copyright (C) 1994-2020 Lua.org, PUC-Rio
> b=lsdbus.open()
> b:request_name("lsdbus.test")
> intf = { name="lsdbus.testif", methods={ Hello={ handler=function() print("hi lsdbus!") end }}}
> s = lsdbus.server.new(b, "/", intf)
> b:loop()
```

**Client** (open a second terminal)

```
$ lua -l lsdbus
Lua 5.3.6  Copyright (C) 1994-2020 Lua.org, PUC-Rio
> b = lsdbus.open()
> p = lsdbus.proxy.new(b, "lsdbus.test", '/', "lsdbus.testif")
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

| D-Bus Type      | D-Bus specifier                   | Lua                  | Example Lua to D-Bus msg...  | ...and back to Lua                |
|-----------------|-----------------------------------|----------------------|------------------------------|-----------------------------------|
| boolean         | `b`                               | `boolean`            | `'b', true`                  | `true`                            |
| integers        | `y`, `n`, `q`, `i`, `u`, `x`, `t` | `number` (integer)   | `'i', 42`                    | `42`                              |
| floating-point  | `d`                               | `number` (double)    | `'d', 3.14`                  | `3.14`                            |
| file descriptor | `h`                               | `number`             |                              |                                   |
| string          | `s`                               | `string`             | `'s', "foo"`                 | `"foo"`                           |
| signature       | `g`                               | `string`             | `'g', "a{sv}"`               | `"a{sv}"`                         |
| object path     | `o`                               | `string`             | `'o', "/a/b/c"`              | `"/a/b/c"`                        |
| variant         | `v`                               | `{SPECIFIER, VALUE}` | `'v', {'i',33 }`             | `33` (or `{'i',33}` with `callr`) |
| array           | `a`                               | `table` (array part) | `'ai', {1,2,3,9}`            | `{1,2,3,9}`                       |
| struct          | `(...)`                           | `table` (array part) | `'(ibs)', {3, false, "hey"}` | `{3, false, "hey"}`               |
| dictionary      | `a{...}`                          | `table` (dict part)  | `'a{si}', {a=1, b=2}`        | `{a=1, b=2}`                      |

**Notes**:

- More examples can be found in the unit tests: `test/message.lua`
- *Variant* is the only type whose conversion is asymmetrical,
  i.e. the input arguments are not equal the result. This is because
  the variant is unpacked automatically. However, in some cases it is
  desirable to get the variant in its raw table form (e.g. when the
  identical value needs to be returned). For that case, the "raw"
  methods `callr` (and `testmsgr`) can be used.
- the tables of deserialized arrays, stucts and variants each have a
  metatable with the `__name` field set to the respective type. This
  permits identifying the original type after the conversion to Lua.

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
> td = lsdb.proxy.new(b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1')
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
lsdb = require("lsdbus.core")
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
`vtab=lsdbus.server.new`. The interface uses the same Lua
representation of the D-Bus interface XML (see below) decorated with
callback functions:

```lua
local interface_table = {
   name="foo.bar.interface0",
   methods = {
      Method1 = {
             { direction=['in'|'out'], name=ARG0NAME, type=TYPESTR },
               ...
              handler=function(vtab, in0, in1...) return out0, out1... end
      }
   },
   properties  = {
      Property1 = {
         access = ['read'|'readwrite'|'write'],
         type = TYPESTR,
         get = function(vtab) return VALUE end
         set = function(vtab, value)
                  -- store, e.g. vtab.Propterty1=value
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
srv = lsdb.server.new(b, PATH, interface_table)
b:loop()
```

The `vtable` table returned by `lsdb.server.new` has the following
fields set: `_bus`, `_slot`, `_path` and `_intf` and apart from these
fields can be freely used for storing state such as property values.

Methods handlers and Properties getters/setters can be directly
invoked on the vtable using the `vt('METHOD')`, `vt:Get('PROPERTY')`
and `vt:Set('PROPERTY')` respectively.

Additionally, `vtable` objects allow emitting declared `signals`
conveniently via `vt:emit('Signal1', arg0, ...)` instead of the longer
`bus:emit_signal(path, intf, member, ...)`. See the the API section
for the available methods.

For further information, take a look at the minimal example
`examples/tiny-server.lua` and the more extensive one
`examples/server.lua`.

#### D-Bus signal matching and callbacks

```lua
function callback(bus, sender, path, interface, member, arg0...)
  -- do something
end

slot = bus:match_signal(sender, path, interface, member, callback)
slot = bus:match(match_expr, callback)
```

These correspond to `sd_bus_match_signal(3)` and `sd_bus_add_match(3)`
respectively.

> **Note**: returning `1` will result in no further callbacks matching
> the same rule to be called (see manpage for details).

**Example**: dump all signals on the system bus:

```lua
local u = require("utils")
local lsdb = require("lsdbus")
local b = lsdb.open('system')
b:match_signal(nil, nil, nil, nil, function (b,...) u.pp(...) end)
b:loop()
```

#### Periodic callbacks

```lua
local function callback(bus, usec)
  -- usec is planned trigger time
end

evsrc = b:add_periodic(period, accuracy, callback, enabled)
```

The `period` and `accuracy` (both in microseconds) correspond to the
same parameters in `sd_event_add_time(3)`.

The `enabled` defines if periodc event should be enabled after creation.
The default value is `true`.

The returned `event_src` object supports methods `set_enabled(int)`
that allows enabling and disabling the event source, and `int get_enabled()`,
that returns event's current mode.

See `examples/periodic.lua` for an example.

#### Unix Signal callbacks

```lua
local function callback(bus, signal)
  print("received signal:", signal)
end
b:add_signal(lsdb.SIGINT, callback)
```

The lsdbus module defines the following constants `SIGINT`, `SIGTERM`,
`SIGUSR1`, `SIGUSR2`.

#### I/O event callback

Add a callback to be called upon IO activity on the given file
descriptor (see `sd_event_add_io(3)`) for details:

*Example:*

```Lua
local function callback(bus, fd, revents)
  print("activity on fd", fd)
end

b:add_io(fd, lsdb.EPOLLIN|lsdb.EPOLLOUT, callback)
```

`events` are any `EPOLLIN`, `EPOLLOUT`, `EPOLLRDHUP`, `EPOLLPRI` or
`EPOLLET`.

An example of using this together with the `linotify` [3] library can
be found under `examples/inotify-io.lua`.

#### Child pid callback

Add a callback to be called upon changes to the given child pid. (see
`sd_event_add_child(3)` and `waitid(2)`).

```Lua
local function callback(b, si)
	utils.pp(si) -- prints {uid=1000,pid=33236,code=2,status=9}
end

b:add_child(pid, lsdb.WEXITED|lsdb.WSTOPPED|lsdb.WCONTINUED, callback)
```

- `status` is either exit code (if code is `CLD_EXITED`) or signal
  otherwise
- `code`: one of `lsdb.CLD_EXITED`, `lsdb.CLD_KILLED`,
  `lsdb.CLD_DUMPED`, `lsdb.CLD_STOPPED`, `lsdb.CLD_TRAPPED`,
  `lsdb.CLD_CONTINUED` (see `si_code` in `waitid(2)` manpage)

#### Returning D-Bus errors

D-Bus errors can be returned by raising a Lua error of the following
form

```Lua
error("org.freedesktop.DBus.Error.InvalidArgs|Something is wrong")
-- or using the standard errors lsdbus.errors
error(string.format("%s|%s", lsdbus.error.INVALID_ARGS, "Something is wrong"))
```

## API

### Functions

| Functions                          | Description                                                    |
|------------------------------------|----------------------------------------------------------------|
| `lsdbus.open(NAME)`                | open bus connection                                            |
| `lsdbus.xml_fromfile(file)`        | parse a D-Bus XML file and return as Lua table                 |
| `lsdbus.xml_fromstr(str)`          | parse a D-Bus XML string and return as Lua table               |
| `lsdbus.find_intf(node, interface` | find and return `interface` in the introspection table         |
| `lsdbus.tovariant(value)`          | encode an arbitray Lua datastructure into a lsdb variant table |
| `lsdbus.tovariant2(value)`         | like above, but just return the value, not the typestr         |

*Example* for `tovariant`

``` lua
-- encode a table into a lsdbus variant
> utils.pp(lsdbus.tovariant{a=1,b={foo='hi'}})
{"a{sv}",{a={"x",1},b={"a{sv}",{foo={"s","hi"}}}}}

-- do the message roundtrip via a variant
> utils.pp(b:testmsg('v', lsdbus.tovariant{a=1,b={foo='hi'}}))
{a=1,b={foo="hi"}}
```

> **Note**: the only limitation of `tovariant` is that for mixed
> array/dictionary tables, numeric indices get converted to strings,
> e.g `{ 1,2, bar='nope' }` becomes `{"1"=1, "2"=2, bar="nope"}`. This
> is a limitation of D-Bus which doesn't allow dictionaries with
> heterogeneous keys.

The `proxy:SetAV` uses the tovariant functions internally.

### Bus connection object

| Methods                                                                       | Description                                  |
|-------------------------------------------------------------------------------|----------------------------------------------|
| `bus:request_name(NAME)`                                                      | see `sd_bus_request_name(3)`                 |
| `bus:release_name(NAME)`                                                      | see `sd_bus_release_name(3)`                 |
| `open, ready = bus:state()`                                                   | see `sd_bus_is_open` and `sd_bus_is_ready`   |
| `slot = bus:match_signal(sender, path, intf, member, callback)`               | see `sd_bus_add_match(3)`                    |
| `slot = bus:match(match_expr, handler)`                                       | see `sd_bus_add_match(3)`                    |
| `bus:emit_properties_changed(propA, propB...)`                                | see `sd_bus_emit_properties_changed(3)`      |
| `bus:emit_signal(path, intf, member, typestr, args...)`                       | see `sd_bus_emit_signal(3)`                  |
| `evsrc = bus:add_signal(SIGNAL)`                                              | see `sd_event_add_signal(3)`                 |
| `evsrc = bus:add_periodic(period, accuracy, callback)`                        | see `sd_event_add_time_relative(3)`          |
| `evsrc = bus:add_io(fd, mask, callback)`                                      | see `sd_event_add_io(3)`                     |
| `evsrc = bus:add_child(pid, options, callback)`                               | see `sd_event_add_child(3)`                  |
| `bus:loop()`                                                                  | see `sd_event_loop(3)`                       |
| `bus:run(usec)`                                                               | see `sd_event_run(3)`                        |
| `bus:exit_loop()`                                                             | see `sd_event_exit(3)`                       |
| `bus:get_fd()`                                                                | see `sd_event_get_fd(3)`                     |
| `table = bus:context()`                                                       | see `sd_bus_message_set_destination(3)` etc. |
| `number = bus:get_method_call_timeout`                                        | see `sd_bus_get_method_call_timeout(3)`      |
| `bus:set_method_call_timeout`                                                 | see `sd_bus_set_method_call_timeout(3)`      |
| `res = bus:testmsg(typestr, args...)`                                         | test Lua->D-Bus->Lua message roundtrip       |
| `ret, res... = bus:call(dest, path, intf, member, typestr, args...)`          | plumbing, prefer lsdbus.proxy                |
| `slot = bus:call_async(callback, dest, path, intf, member, typestr, args...)` | plumbing async method invocation             |
| `slot = bus:add_object_vtable(path, vtab_raw)`                                | plumbing, use lsdbus.server instead          |


**Notes**:

- `lsdb.open` accepts an optional string parameter to indicate which
  bus to open:
    - `new` (`sd_bus_open`)
    - `system` (`sd_bus_system`)
    - `user` (`sd_bus_user`)
    - `default` (`sd_bus_default`)
    - `default_system` (`sd_bus_default_system`)
    - `default_user` (`sd_bus_default_user`)

  If not given, default is `new'`

- `evsrc` (event source) objects are **not** cleaned up (`unref`ed)
  when garbage collected but set to *floating*, which means they will
  live until the event loop is destroyed. To explicitely disable and
  destroy an event source, call its `unref` method.

> **Note**: upon being collected the `default_*` type bus objects are
> only `flush`ed and `unref`ed, whereas on non default (`new`,
> `system` and `user`) bus objects `sd_bus_flush_close_unref` is
> called.

> **Note**: if there can be other in-process users that use the event
> loop (i.e. that call `loop` or `run`) in different threads and Lua
> states, to avoid interference it is advisable to create a new bus
> and event loop (using the `new`, `system` or `user` open variants).

### lsdbus.proxy

| Method                                         | Description                                           |
|------------------------------------------------|-------------------------------------------------------|
| `prxy = lsdbus.proxy.new(bus, srv, obj, intf)` | constructor                                           |
| `prxy(method, arg0, ...)`                      | call a D-Bus method                                   |
| `prxy:call(method, arg0, ...)`                 | same as above, long form                              |
| `prxy:HasMethod(method)`                       | check if prxy has a method with the given name        |
| `prxy:callt(method, ARGTAB)`                   | call a method with a table of arguments               |
| `prxy:calltt(method, ARGTAB)`                  | like `callt`, but returns a result table              |
| `prxy:call_async(method, callback, ARGTAB)`    | call a method asynchronously (returns slot)           |
| `prxy:callr(method, arg0, ...)`                | raw call, will not unpack variants                    |
| `prxy:Get(name)`                               | get a properties value                                |
| `prxy.name`                                    | short form, same as previous                          |
| `prxy:Set(name, value)`                        | set a property                                        |
| `prxy:SetAV(name, value)`                      | set a property (auto convert variants)                |
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
- `SetAV` ("auto variant") will use `tovariant` to automatically
  convert standard Lua types to lsdbus variants. Currently supported
  are `a{sv}`, `v`, `av` and `a{iv}`.
- see *Internals* about how `lsdbus.proxy` works.

### lsdbus.server

| Method                                    | Description                                                |
|-------------------------------------------|------------------------------------------------------------|
| `vt = lsdbus.server.new(bus, path, intf)` | create a new obj with the given path and interface         |
| `vt:call('METHOD', ...)`                  | locally call the D-Bus method handler                      |
| `vt(METHOD, ...)`                         | same as above                                              |
| `vt:Get(PROPERTY)`                        | locally call the `get` function                            |
| `vt:Set(PROPERTY, value)`                 | locally call the `set` function                            |
| `vt:emit(SIGNAL, args...)`                | emit a signal that is defined in the servers interface     |
| `vt:emitPropertiesChanged(prop0, ...)`    | emit a PropertiesChanged signal for one or more properties |
| `vt:emitAllPropertiesChanged(filter)`     | emit a PropertiesChanged signal for all properties         |
| `vt:HasMethod(METHOD)`                    | check if vt has a method                                   |
| `vt:HasProperty(PROPERTY)`                | check if vt has a property                                 |
| `vt:HasSignal(SIGNAL)`                    | check if vt has a signal                                   |
| `vt:get_interface()`                      | return the original interface                              |
| `vt:unref()`                              | remove the interface and release the resources             |
| `error("dbus.error.name\|message")`       | return a D-Bus error and message from a callback           |

**Notes**:

- The `emitAllPropertiesChanged(filter)` takes an optional filter
  function which accepts the property name and property table and
  returns true or false depending on whether the property shall be
  included in the `PropertiesChanged` signal not.
- the vtable slot (`srv.slot`) is garbage collected which will remove
  the respective dbus interface. Call `srv:unref()` to explicitely
  remove the interface.

### slots

`slot` (`sd_bus_slot`) objects are returned by `match`,
`match_signal`, `server.new` and `call_async` calls.

| Method    | Description                               |
|-----------|-------------------------------------------|
| `unref()` | remove slot. calls `sd_bus_slot_unref(3)` |

The behavior upon garbage collection depends on the slot type:

- `vtable`: `unref`ed, resources freed
- `match*`: set to floating (i.e. will continue to exist as long as
  bus does).
- `call_async`: `unref`ed, resources freed

> **Note**: you must hold a reference to a `vtable` slot to prevent is
> being garbage collected and removed. Typically one just stores a
> reference to the `srv` object return by `server.new`.


### event sources

`evsrc` (`sd_event_source`) objects are returned by `bus:add_signal`,
`bus:add_periodic`, `bus:add_io` and `bus:add_child`.

| Method                 | Description                                                                           |
|------------------------|---------------------------------------------------------------------------------------|
| `set_enabled(enabled)` | `enabled`: `lsdbus.SD_EVENT_[ON\|OFF\|ONESHOT]`. see `sd_event_source_set_enabled(3)` |
| `get_enabled()`        | returns `lsdbus.SD_EVENT_[ON\|OFF\|ONESHOT]`. see `sd_event_source_get_enabled(3)`    |
| `unref()`              | remove event source. calls `sd_event_source_unref(3)`                                 |

> **Note**: `evsrc` (event source) objects are **not** released
> (`unref`ed) when they go out of scope (i.e. are garbage collected)
> but are set to *floating*. This means they will live until the event
> loop is destroyed. To explicitely destroy an event source, call its
> `unref` method.

Thus, there is no need to store a reference to an `evsrc` object
*unless* you intend to remove it before the program ends.

## Internals

### Introspection

The fourth parameter of `lsdbus.proxy.new` is typically a string
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

prx = proxy.new(b, 'foo.bar.ick1', '/my/nice/obj', intf)
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

## Tests

After installing lsdbus, the tests can be run from the project root as

```
$ ./scripts/test-runner.sh -r 3 -s
Launching peer test server...
running tests with Lua 5.4, luaunit args  -r 3 -s
using bus: default
..................................................................
Ran 66 tests in 0.166 seconds, 66 successes, 0 failures
OK
tests completed with exit code  0
Stopping peer test server with PID  1790834
```

This also starts the testserver peer service. The environment variable
`LUA_VERSION` can be set to specifiy which Lua version to use. All
arguments to the script are passed to luaunit.

To run in dedicated D-Bus session:

``` lua
$ dbus-run-session -- ./scripts/test-runner.sh
...
```

## License

LGPLv2. A portion of the lsdbus type conversion is based on code from
systemd.

## FAQ

### Error `System.Error.ENOTCONN: Transport endpoint is not connected`

This happens when a bus is created (`lsdb.open(...)`) and only used
after more than ~30s. The exact reason is not clear. The workaround is
to immediately use the bus (`request_name`, `proxy.new` or
`server.new`) after opening.

Of course, this can also happen if a non-default bus (open flags
`new`, `user` and `system`) goes out of scope and is collected.

### `System.Error.ENOTCONN` after exiting loop

For some reason, after exiting the sd_event loop using `exit_loop`,
the bus is disconnected and can't be used anymore. The simple
workaround is to perform any actions requiring the bus before exiting
the loop.

## ChangeLog

(only API changes)

- `b:add_periodic`: accepts additional argument `enabled` which defines
  if periodic event should be enabled or disabled after creation. The
  default value is `true` == `enabled`.
- added `proxy:SetAV` (Auto Variant) property set method
- `lsdbus.server`: prefixing of internal fields (`.bus`, `.path`,
  `.slot`, `.intf`) with `_` to prevent name collisions with user
  fields. The low-level vtable is moved to `._vt)`.
- constructors are now functions: use `lsdbus.server.new` and
  `lsdbus.proxy.new` instead of `lsdbus.server:new` and
  `lsdbus.proxy:new` respectivly.
- `lsdb.open()` now defaults to `new`, i.e. `sd_bus_open(3)`. This is
  the safer default, since it will not piggy back onto a potentially
  existing event loop.
- added `bus:get_fd()` (see `sd_event_get_fd(3)`)
- added `bus:release_name`
- **vtab slots are now also garbage collected**. So make sure to hold
  onto the vtab object returned by `server:new` (this itself contains
  a ref to the slot `.slot`) or the interface will dissappear after
  the next GC cycle.
- `b:add_signal`: takes a numeric signals numbers instead of a
  string. the `lsdbus` module defines constants for supported signals.
- additional parameter for callbacks. The callbacks for `match`,
  `match_signal`, `call_async`, `add_signal`, `add_periodic` and
  `add_io` receive the `bus` object as an additional first
  parameter. This avoids the need to pass the bus (e.g. for
  `b:exit_loop()` via the scope.
  The server method `handler` and property `get` and `set` handlers
  receive the `vtable` table returned from `lsdbus.server.new`. Again
  this avoids the need to pass the `bus` object in via the scope and
  moreover provides a table that can be freely used to store state
  such as property values.

## References

[1] https://github.com/bluebird75/luaunit.git  
[2] https://github.com/kmarkus/uutils.git  
[3] https://github.com/hoelzro/linotify  
