local M = {}

---@param s string
---@return lib.Iterator<string>
M.splitlines = function(s)
  local normalized = string.gsub(s, "\r\n?", "\n")
  return vim.gsplit(normalized, "\n", { plain = true })
end

return M
