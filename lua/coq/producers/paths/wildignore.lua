local M = {}

---@param glob string
---@return string
M.glob_to_lua = function(glob)
  local escaped = string.gsub(glob, "[%%%(%)%.%[%]%+%-%^%$]", "%%%0")
  escaped = string.gsub(escaped, "%*", ".*")
  escaped = string.gsub(escaped, "%?", ".")
  return "^" .. escaped .. "$"
end

---@param wildignore string
---@return string[]
M.compile = function(wildignore)
  local pats = {}
  for entry in vim.gsplit(wildignore, ",", { plain = true }) do
    if entry ~= "" then
      table.insert(pats, M.glob_to_lua(entry))
    end
  end
  return pats
end

---@param ignores string[]
---@param name string
---@param full string
---@return boolean
M.is_ignored = function(ignores, name, full)
  for _, p in pairs(ignores) do
    if string.find(name, p) or string.find(full, p) then
      return true
    end
  end
  return false
end

return M
