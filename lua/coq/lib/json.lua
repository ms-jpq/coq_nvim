local M = {}

M.DECODE_OPTS = { luanil = { object = true, array = true } }
M.PRETTY_OPTS = { sort_keys = true, indent = [[  ]] }

---@param value any
---@param pretty? boolean
---@return string
M.encode = function(value, pretty)
  return vim.json.encode(value, pretty and M.PRETTY_OPTS or nil)
end

---@param s string
---@return any? value
---@return string? err
M.decode = function(s)
  local ok, value = pcall(vim.json.decode, s, M.DECODE_OPTS)
  if ok then
    return value
  end
  return nil, value
end

return M
