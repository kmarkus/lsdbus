local lu = require("luaunit")
local lsdb = require("lsdbus")
local proxy = lsdb.proxy
local have_unistd, unistd = pcall(require, "posix.unistd")

local testconf = debug.getregistry()['lsdbus.testconfig']

local TestCredentials = {}

function TestCredentials:setup()
	if not have_unistd then
		lu.skip("no luaposix")
	end

	self.b = lsdb.open(testconf.bus)
end

function TestCredentials:teardown()
	self.b = nil
end

function TestCredentials:TestCredentials()
	local euid, pid = unistd.geteuid(), unistd.getpid()
	local p = proxy.new(self.b, "lsdbus.test", "/1", "lsdbus.test.testintf0")
	local reuid, rpid = p('GetCredentials')
	lu.assert_equals(euid, reuid)
	lu.assert_equals(pid, rpid)
end

return TestCredentials

