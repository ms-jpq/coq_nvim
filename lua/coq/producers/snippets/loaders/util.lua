local M = {}

---@param src snippets.Source
---@param items snippets.Item[]
---@return snippets.Sourced
M.sourced = function(src, items)
  return {
    kind = src.kind,
    path = src.path,
    mtime = src.mtime,
    snippets = items,
  }
end

return M
