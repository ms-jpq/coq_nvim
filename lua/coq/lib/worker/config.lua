-- Bootstrap config: main encodes a definition; worker parses the raw blob
-- (after it has set package.path so requires can resolve).

local M = {}

M.encode = function(definition)
  local methods = {}
  for name, decl in pairs(definition) do
    if name ~= "init" then
      if type(decl) == "table" and decl.streaming then
        methods[name] = { kind = "stream", dump = string.dump(decl.fn) }
      else
        methods[name] = { kind = "rpc", dump = string.dump(decl) }
      end
    end
  end
  return vim.mpack.encode {
    init = definition.init and string.dump(definition.init) or nil,
    methods = methods,
    package_path = package.path,
    package_cpath = package.cpath,
  }
end

M.parse = function(raw)
  local state = raw.init and load(raw.init)() or {}
  local methods = {}
  for name, m in pairs(raw.methods) do
    methods[name] = { kind = m.kind, fn = load(m.dump) }
  end
  return state, methods
end

return M
