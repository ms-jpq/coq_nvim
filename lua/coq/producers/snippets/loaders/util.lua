local M = {}

---@param src snippets.Source
---@param filetypes string[]
---@param items snippets.Item[]
---@return snippets.Sourced
M.sourced = function(src, filetypes, items)
  return {
    kind = src.kind,
    path = src.path,
    mtime = src.mtime,
    filetypes = filetypes,
    snippets = items,
  }
end

return M
