local convert = function (spec)
  local tb = {}
  for k, v in pairs(lsp.protocol[spec]) do
    if type(k) == "string" and type(v) == "number" then
      tb[k] = v
    end
  end
  return tb
end

local specs = {"CompletionItemKind", "InsertTextFormat"}
