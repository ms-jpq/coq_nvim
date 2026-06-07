local M = {}

---Render an LSP snippet body as it would appear if accepted, with
---placeholders shown as their literal default text. For preview surfaces
---(ghost text, PUM info, etc.) — actual expansion runs through
---`vim.snippet.expand`.
---
---Handles the visible subset of the LSP snippet grammar: escapes, tabstops
---with defaults, bare tabstops, choices, and variable placeholders. We can't
---reach into nvim's internal parser without depending on private APIs, but
---this covers what shows up in the bundles.
---@param body string
---@return string
M.preview = function(body)
  -- Protect escapes (`\$`, `\}`, `\\`) with sentinel bytes so they don't get
  -- consumed by the snippet-syntax substitutions below.
  local out = string.gsub(body, "\\(.)", "\1%1\1")
  out = string.gsub(out, "%${(%d+)|([^|]*)|}", function(_, opts)
    return string.match(opts, "([^,]*)") or "" -- ${1|a,b,c|} → a
  end)
  out = string.gsub(out, "%${(%d+):([^}]*)}", "%2") -- ${1:default} → default
  out = string.gsub(out, "%${(%w+):([^}]*)}", "%2") -- ${VAR:default} → default
  out = string.gsub(out, "%${%w+}", "") -- ${1} / ${VAR} → empty
  out = string.gsub(out, "%$%w+", "") -- $1 / $VAR → empty
  out = string.gsub(out, "\1(.)\1", "%1") -- restore escaped literals
  return out
end

return M
