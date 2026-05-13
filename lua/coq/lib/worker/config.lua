local encode = function(definition)
  local methods = {}
  for name, fn in pairs(definition) do
    if name ~= "init" then
      methods[name] = string.dump(fn)
    end
  end
  return vim.mpack.encode {
    init = definition.init and string.dump(definition.init) or nil,
    methods = methods,
    package_path = package.path,
    package_cpath = package.cpath,
  }
end

local parse = function(raw)
  local state = raw.init and load(raw.init)() or {}
  local methods = {}
  for name, dump in pairs(raw.methods) do
    methods[name] = load(dump)
  end
  return state, methods
end

return { encode = encode, parse = parse }
