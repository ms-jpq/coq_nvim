local sanitize = function(spec)
  local tb = {}
  for k, v in pairs(spec) do
    if type(k) == "string" and type(v) == "number" then
      tb[k] = v
    end
  end
  return tb
end

local lookup = sanitize(vim.lsp.protocol.CompletionItemKind)
local json = vim.fn.json_encode(lookup)

vim.fn.writefile({json}, "/dev/stdout")

os.exit(0)

