local DECODE_OPTS = { luanil = { object = true, array = true } }
local PRETTY_OPTS = { sort_keys = true, indent = [[  ]] }

local M = {}

---@param value any
---@param pretty? boolean
---@return string
M.encode = function(value, pretty)
  return vim.json.encode(value, pretty and PRETTY_OPTS or nil)
end

---@param s string
---@return any? value
---@return string? err
M.decode = function(s)
  local ok, value = pcall(vim.json.decode, s, DECODE_OPTS)
  if ok then
    return value
  end
  return nil, value
end

return M
