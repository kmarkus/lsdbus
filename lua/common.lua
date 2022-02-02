local M = {}

local concat = table.concat

function M.met2its(mtab)
   local i = {}
   for _,a in ipairs(mtab or {}) do
      if a.direction=='in' then i[#i+1] = a.type end
   end
   return concat(i)
end

function M.met2ots(mtab)
   local o = {}
   for _,a in ipairs(mtab or {}) do
      if a.direction=='out' then o[#o+1] = a.type end
   end
   return concat(o)
end

function M.met2names(mtab)
   local nin, nout = {}, {}
   for _,m in ipairs(mtab or {}) do
      if not m.name then error("missing argument name") end
      if m.direction=='in' then
	 nin[#nin+1] = m.name
      elseif m.direction=='out' then
	 nout[#nout+1] = m.name
      end
   end
   return concat(nin, '\0') .. '\0' .. concat(nout, '\0') .. '\0\0'
end

function M.signal2ts(stab)
   local s = {}
   for _,arg in ipairs(stab or {}) do s[#s+1] = arg.type end
   return concat(s)
end

function M.signal2names(stab)
   local names = {}
   for _,arg in ipairs(stab or {}) do
      if not arg.name then error("missing argument name") end
      names[#names+1] = arg.name
   end
   return concat(names, '\0') .. '\0\0'
end


return M
