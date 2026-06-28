local M = {}

M.L, M.R = "‹", "›"

---@param body string
---@return string
M.preview = function(body)
  local out = string.gsub(body, "\\(.)", "\1%1\1")

  out = string.gsub(out, "%${(%d+)|([^|]*)|}", function(_, opts)
    return M.L .. (string.match(opts, "([^,]*)") or "") .. M.R
  end)
  out = string.gsub(out, "%${(%d+):([^}]*)}", M.L .. "%2" .. M.R)
  out = string.gsub(out, "%${(%w+):([^}]*)}", M.L .. "%2" .. M.R)
  out = string.gsub(out, "%${%w+}", M.L .. M.R)
  out = string.gsub(out, "%$%w+", M.L .. M.R)
  out = string.gsub(out, "\1(.)\1", "%1")

  return out
end

return M
