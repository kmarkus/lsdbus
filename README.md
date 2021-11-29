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

| What            | D-Bus                             | Lua representation     | example                      | Result              |
|-----------------|-----------------------------------|------------------------|------------------------------|---------------------|
| boolean         | `b`                               | `boolean`              | `'b', true`                  | `true`              |
| integers        | `y`, `n`, `q`, `i`, `u`, `x`, `t` | `number` (integer)     | `'i', 42`                    | `42`                |
| floating-point  | `d`                               | `number` (double)      | `'d', 3.14`                  | `3.14`              |
| file descriptor | `h`                               | `number`               |                              |                     |
| string          | `s`                               | `string`               | `'s', "foo"`                 | `"foo"`             |
| signature       | `g`                               | `string`               | `'g', a{sv}`                 | `a{sv}`             |
| object path     | `o`                               | `string`               | `'o', "/a/b/c"`              | `"/a/b/c"`          |
| variant         | `v`                               | `{ SPECIFIER, VALUE }` | `'v', {'i', 33 }`            | `33`                |
| array           | `a`                               | `table` (array part)   | `'ai', {1,2,3,4}`            | `{1,2,3}`           |
| struct          | `(...`)                           | `table` (array part)   | `'(ibs)', {3, false, "hey"}` | `{3, false, "hey"}` |
| dictionary      | `a{...}`                          | `table` (dict part)    | `'a{ss}', {a=1, b=2}`        | `{a=1, b=2}`        |




Note that the variant is the only type that is unsymmetric, i.e. the
input arguments are not equal the result. This is because the variant
is unpacked automatically.


```
u=require("utils")
l=require("lsdbus")
b = l.open()
u.pp(b:testmsg(typestr, arg0, ...))
```

### Client API

#### lsdb_proxy

#### plumbing API

The low-level API can be used if the proxy client API is unavailable
(e.g. no introspection is available).


### Server API


## License

LGPLv2 as the lsdbus type conversion is based on code from systemd.
