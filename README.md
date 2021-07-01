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

To run the tests, get a copy of `luaunit`:

either 

```sh
sudo apt-get install lua-unit` 
```

or 

`git clone https://github.com/bluebird75/luaunit.git`

Either install the luaunit.lua file or copy it to the `test` directory
in this project.

## Usage
Please see the examples provided.




