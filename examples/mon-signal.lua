local u = require("utils")
local lsdb = require("lsdbus")

local b = lsdb.open('default_system')

-- b:match_signal(sender, path, interface, member)
--
-- b:match_signal(sender, path, interface, member)
-- b:match_signal(nil, nil, nil, 'PropertiesChanged', function (...) u.pp({...}) end)
-- b:match_signal(nil, '/org/freedesktop/UPower/devices/battery_BAT0', nil, nil, function (...) u.pp({...}) end)
-- b:match_signal(nil, nil, 'fi.w1.wpa_supplicant1.BSS', nil, function (...) u.pp({...}) end)

-- match all:
b:match_signal(nil, nil, nil, nil, function (...) u.pp{...} end)

b:loop()
