-- Deep-equality that uses `==` at leaves. Under LuaJIT this transparently
-- handles cdata vs number comparisons (FFI extends `==` across types),
-- which luaunit's assertEquals deep-compare does not.

local function teq(a, b)
   if type(a) == 'table' and type(b) == 'table' then
      for k, v in pairs(a) do
         if not teq(v, b[k]) then return false end
      end
      for k in pairs(b) do
         if a[k] == nil and rawget(b, k) ~= nil then return false end
      end
      return true
   end
   return a == b
end

return teq
