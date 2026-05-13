local proto = require "coq.lib.worker.proto"

local M = {}

local classify = function(decl)
  if type(decl) == "table" and decl.streaming then
    return { mode = proto.MODE.STREAM, dump = string.dump(decl.fn) }
  end
  return { mode = proto.MODE.RPC, dump = string.dump(decl) }
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
  local state = raw.init and load(raw.init)() or {}
  local methods = {}
  for name, m in pairs(raw.methods) do
    methods[name] = { mode = m.mode, fn = load(m.dump) }
  end
  return state, methods
end

return M
