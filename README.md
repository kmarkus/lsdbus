# lsdbus

The `lsdbus` module provides Lua bindings to the `sd_bus` D-Bus client
library. This extension marries the two single greatest achievements
of mankind: `Lua` and `D-Bus`.

The goal is to provide a compact yet useful subset of the `sd_bus` and
`sd_event` APIs to cover typical use-cases.

*The `L` stands for 'likeable'.

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Installing](#installing)
- [Usage](#usage)
    - [Bus connection](#bus-connection)
    - [Type mapping](#type-mapping)
        - [Testmsg](#testmsg)
    - [Client API](#client-api)
        - [lsdb_proxy](#lsdb_proxy)
        - [plumbing API](#plumbing-api)
        - [Emitting signals](#emitting-signals)
    - [Server API](#server-api)
        - [Event loop](#event-loop)
        - [D-Bus signal matching and callbacks](#d-bus-signal-matching-and-callbacks)
        - [Periodic callbacks](#periodic-callbacks)
        - [Unix Signal callbacks](#unix-signal-callbacks)
        - [Registering Interfaces: Properties, Methods and Signal](#registering-interfaces-properties-methods-and-signal)
- [Internals](#internals)
    - [Introspection](#introspection)
- [License](#license)
- [References](#references)

<!-- markdown-toc end -->


## Installing

First, ensure that the correct packages are installed. For Debian
based distributions:

```sh
$ sudo apt-get install build-essential git cmake lua5.3 liblua5.3-dev libsystemd-dev libmxml-dev
```

To run the tests, install `lua-unit` or install it directly from here [2].

## Usage

### Bus connection

Before doing anything, it is necessary to connect to a bus:

```lua
lsdb = require("lsdbus")
b = lsdb.open()
```

`lsdb.open` accepts an optional string parameter to indicate which bus
to open: `default`, `system`, `user`, `default_system`, `default_user`
correspond function as described in `sd_bus_default(3)`.

Optionally, a well-known name can be registered as follows:

```lua
b:request_name("foo.bar.myservice")
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
| signature       | `g`                               | `string`             | `'g', a{sv}`                 | `a{sv}`             |
| object path     | `o`                               | `string`             | `'o', "/a/b/c"`              | `"/a/b/c"`          |
| variant         | `v`                               | `{SPECIFIER, VALUE}` | `'v', {'i', 33 }`            | `33`                |
| array           | `a`                               | `table` (array part) | `'ai', {1,2,3,4}`            | `{1,2,3}`           |
| struct          | `(...)`                           | `table` (array part) | `'(ibs)', {3, false, "hey"}` | `{3, false, "hey"}` |
| dictionary      | `a{...}`                          | `table` (dict part)  | `'a{si}', {a=1, b=2}`        | `{a=1, b=2}`        |


*Notes*

- More examples can be found in the unit tests: `test/message.lua`
- *Variant* is the only type whose conversion is unsymmetric, i.e. the
  input arguments are not equal the result. This is because the
  variant is unpacked automatically.


### Client API

There are two client APIs: the high level `lsdbus_proxy` API uses
introspection to create a proxy object, that can be used to
conveniently call methods or get/set properties. The plumbing API
allows calling methods however more arguments (destination, path,
interface, member, typestring and args) need to be provided.

#### lsdb_proxy

**Example**

```lua
> lsdb = require("lsdbus")
> b = lsdb.open("system")
> proxy = require("lsdbus_proxy")
> td = proxy:new(b, 'org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1')
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

Unlike the low-level `call` function, no D-Bus types need to be provided.

**lsdbus_proxy methods**

| Method                                         | Description                                           |
|------------------------------------------------|-------------------------------------------------------|
| `prxy = lsdbus_proxy:new(bus, srv, obj, intf)` | constructor                                           |
| `prxy(method, arg0, ...)`                      | call a D-Bus method                                   |
| `prxy:call(method, arg0, ...)`                 | same as above, long form                              |
| `prxy:HasMethod(method)`                       | check if prxy has a method with the given name        |
| `prxy:callt(method, ARGTAB)`                   | call a method with a table of arguments               |
| `prxy:Get(name)`                               | get a property                                        |
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
- see *Internals* about how `lsdbus_proxy` works.

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

respectively.

Any callback can use the method `b:context()` to retrieve additional
information which depending on the callback type may include

- `interface`
- `path`
- `member`
- `sender`
- `destination`

(these are retrieved using `sd_bus_get_current_message(3)` and the
respective `sd_bus_message_get_*(3)` functions).

#### D-Bus signal matching and callbacks

```lua
function callback(sender, path, interface, member, arg0...)
	-- do something
end

b:match_signal(sender, path, interface, member, callback)
b:match(match_expr, callback)
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

#### Registering Interfaces: Properties, Methods and Signal

The format used is the same Lua representation of the D-Bus interface
XML (see below) extended with callbacks. Take a look at the entirely
self-explaining minimal example `examples/tiny-server.lua`.

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
b:request_name(WELL_KNOWN_NAME)
b:add_object_vtable(PATH, interface_table)
b:loop()
```

**Note**: the signals specification currently only serves for
introspection, there is no function attached to it. However a
convenience function (`b:emit(arg0...)` ?) may be added in the future.

## Internals

### Introspection

The fourth parameter of `lsdbus_proxy:new` is typically a string
interface name, whose XML is then retrieved using the standard
introspection interfaces and converted to a Lua representation using
`lsdb.xml_fromstr(xml)`. It is available as `proxy.intf`.

However, if introspection is not available, this Lua interface table
can be manually specified and provided directly as the fourth
parameter instead of a string. This way, `lsdb_proxy` can be used also
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

