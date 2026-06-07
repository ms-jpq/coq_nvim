local M = {}

local L, R = "‹", "›"

---@param body string
---@return string
M.preview = function(body)
  local out = string.gsub(body, "\\(.)", "\1%1\1")

  out = string.gsub(out, "%${(%d+)|([^|]*)|}", function(_, opts)
    return L .. (string.match(opts, "([^,]*)") or "") .. R
  end)
  out = string.gsub(out, "%${(%d+):([^}]*)}", L .. "%2" .. R)
  out = string.gsub(out, "%${(%w+):([^}]*)}", L .. "%2" .. R)
  out = string.gsub(out, "%${%w+}", L .. R)
  out = string.gsub(out, "%$%w+", L .. R)
  out = string.gsub(out, "\1(.)\1", "%1")

  return out
end

return M
