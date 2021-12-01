# lsdbus

The `lsdbus` module provides Lua bindings to the `sd_bus` D-Bus client
library. This extension marries the two single greatest achievements
of mankind: `Lua` and `D-Bus`.

*The `L` stands for 'likeable'.

## Prerequsites
1. cmake
1. libsystemd >= 236
1. lua v5.3
1. libmxml
1. luaunit

## Installing
First, ensure that the correct packages are installed. For a debian
distribution like Ubuntu:

`sudo apt-get install build-essential git cmake lua5.3 liblua5.3-dev libmxml-dev`

To run the tests, get a copy of `lua-unit`:

either 

```sh
sudo apt-get install lua-unit` 
```

or 

`git clone https://github.com/bluebird75/luaunit.git`

Either install the luaunit.lua file or copy it to the `test` directory
in this project.

## Usage

### Type mapping

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
| struct          | `(...`)                           | `table` (array part) | `'(ibs)', {3, false, "hey"}` | `{3, false, "hey"}` |
| dictionary      | `a{...}`                          | `table` (dict part)  | `'a{si}', {a=1, b=2}`        | `{a=1, b=2}`        |


*Notes*

- Many more examples can be found in the unit tests:
  `test/message.lua`

- *Variant* is the only type whose conversion is unsymmetric, i.e. the
  input arguments are not equal the result. This is because the
  variant is unpacked automatically.

**Testmsg**

To faciliate testing message conversion, lsdbus provides a special
function `testmsg`, that accepts a message specifier and value,
creates a D-Bus message from it and converts it back to Lua:

```lua
> lsdb = require("lsdbus")
> b = lsdb.open()
> u = require("utils")
> u.pp(b:testmsg('b', true))
true
> u.pp(b:testmsg('ai', {1,2,3,4}))
{1,2,3,4}
> u.pp(b:testmsg('a{s(is)}', { one = {1, 'this is one'}, two = {2, 'this is two'} })
{one={1,"this is one"},two={2,"this is two"}}
> u.pp(b:testmsg('a{sv}', { foo={'s', "nirk"}, bar={'d', 2.718}, dunk={'b', false}})
{foo="nirk",dunk=false,bar=2.718}
```

The above uses the tiny `uutils` [1] library for printing tables.

### Bus connection

Before doing anything, it is necessary to connect to a bus:

```lua
lsdb = require("lsdbus")
b = lsdb.open()
```

`lsdb.open` accepts an optional string parameter to indicate which bus
to open: `default`, `system`, `user`, `default_system`, `default_user`
correspond function as described in `sd_bus_default(3)`.

### Client API

There are two client APIs: the high level proxy API uses introspection
to create a proxy object, that can be used to call methods or access
properties. The plumbing API allows direct calling of methods.

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

Unlike with the plumbing API, no D-Bus specifiers need to be provided.

**Proxy Methods**

| Method                                  | Description                                           |
|-----------------------------------------|-------------------------------------------------------|
| `lsdbus_proxy:new(bus, srv, obj, intf)` | constructor                                           |
|-----------------------------------------|-------------------------------------------------------|
| `prxy(method, arg0, ...)`               | call a D-Bus method                                   |
| `prxy:call(method, arg0, ...)`          | long form, same as above                              |
| `prxy:HasMethod(method)`                | check if prxy has a method with the given name        |
| `prxy:callt(method, ARGTAB)`            | call a method with a table of arguments               |
|-----------------------------------------|-------------------------------------------------------|
| `prxy:Get(name)`                        | get a property                                        |
| `prxy.name`                             | short form, same as previous                          |
| `prxy:Set(name, value)`                 | set a property                                        |
| `prxy.name = value`                     | short form for setting a property to value            |
| `prxy:GetAll(filter)`                   | get all properties that match the optional filter     |
| `prxy:SetAll(t)`                        | set all properties from a table                       |
| `prxy:HasProperty(prop)`                | check if prxy has a property of the given name        |
|-----------------------------------------|-------------------------------------------------------|
| `prxy:Ping`                             | call the `Ping` method on `org.freedesktop.DBus.Peer` |
| `prxy:error`                            | error handler, override to customize behavior         |


*Notes*

- `callt` is a convenience method that works only if the method has
  named arguments: `b:callt{argA=2, argB="that"}`.

- `GetAll` accepts a filter which can be either
  1. a string `read`|`readwrite`|`write`
  2. a filter function that accepts `(name, value, description)` and returns
  `true` or `false` depending on whether the value shall be included
  or not.

- see *Internals* about how `lsdbus_proxy` works.

#### plumbing API

**Syntax**

```lua
ret, res0, ... = bus:call(dest, path, intf, member, spec, arg0, ...)
```

in case of success `ret` is `true` and `res0`, `res1`, ... are the
return values of the call.

if case of failure `ret` is `false` and `res0` is a table of the form
`{ERROR, message}`.


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

### Server API

#### Event loop

```lua
b:loop()
```

#### Signal handling

```lua
bus:match_signal(sender, path, interface, member, callback)
bus:match(match_expr, callback);

function callback(sender, path, interface, member, arg0...)
	-- do something
end
```

These correspond to `sd_bus_match_signal` and `sd_bus_add_match`
respectively.

**Example**:

Match and dump all signals on the system bus:

```lua
local u = require("utils")
local lsdb = require("lsdbus")
local b = lsdb.open(system')
b:match_signal(nil, nil, nil, nil, function (...) u.pp({...}) end)
b:loop()
```

#### Properties

#### Methods


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
local node = {
   {
      name = 'de.mkio.test',

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
}
```

## License

LGPLv2 as the lsdbus type conversion is based on code from systemd.


## References

[1] https://github.com/kmarkus/uutils.git
