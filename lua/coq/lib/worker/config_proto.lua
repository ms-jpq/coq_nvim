local M = {}

M.streaming = function(fn)
  return { streaming = true, fn = fn }
end

M.is_streaming = function(decl)
  return type(decl) == "table" and decl.streaming == true
end

local classify = function(decl)
  if M.is_streaming(decl) then
    return { streaming = true, dump = string.dump(decl.fn) }
  end
  return { streaming = false, dump = string.dump(decl) }
end

M.encode = function(definition)
  local methods = {}
  for name, decl in pairs(definition) do
    if name ~= "init" then
      methods[name] = classify(decl)
    end
  end
  return vim.mpack.encode {
    init = definition.init and string.dump(definition.init),
    methods = methods,
    package_path = package.path,
    package_cpath = package.cpath,
  }
end

M.decode = function(raw)
  if raw.init then
    load(raw.init)()
  end
  local methods = {}
  for name, m in pairs(raw.methods) do
    methods[name] = { streaming = m.streaming, fn = load(m.dump) }
  end
  return methods
end

return M
