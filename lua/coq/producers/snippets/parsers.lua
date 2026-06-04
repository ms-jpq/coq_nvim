local M = {}

---@param _src snippets.Source
---@return snippets.Item[]
M.bundle = function(_src)
  return {}
end

---@param _src snippets.Source
---@return snippets.Item[]
M.neosnippet = function(_src)
  return {}
end

---@param _src snippets.Source
---@return snippets.Item[]
M.lsp = function(_src)
  return {}
end

---@type table<snippets.Kind, fun(src: snippets.Source): snippets.Item[]>
M.by_kind = {
  bundle = M.bundle,
  neosnippet = M.neosnippet,
  lsp = M.lsp,
}

return M
