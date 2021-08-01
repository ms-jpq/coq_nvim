local sanitize = function(spec)
  local tb = {[vim.type_idx] = vim.types.dictionary}
  for k, v in pairs(spec) do
    if type(k) == "string" and type(v) == "number" then
      tb[k] = v
    end
  end
  return tb
end

local lookup = {}

for key, val in pairs(vim.lsp.protocol) do
  if type(val) == "table" then
    lookup[key] = sanitize(val)
  end
end

local json = vim.fn.json_encode(lookup)

vim.fn.writefile({json}, "/dev/stdout")

os.exit(0)
