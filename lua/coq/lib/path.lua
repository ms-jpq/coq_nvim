local lib = require "coq.lib"
local set = require "coq.lib.set"

local M = {}

M.HOME = vim.uv.os_homedir() or ""

---@param is_windows boolean
---@return lib.Set<string>
M.seps = function(is_windows)
  return set.new(is_windows and { "/", "\\" } or { "/" })
end

local DRIVE_PAT = "^%a:[/\\]"

---@param is_windows boolean
---@param p string
---@return boolean
M.is_absolute = function(is_windows, p)
  if is_windows then
    return vim.startswith(p, "/") or vim.startswith(p, "\\") or string.match(p, DRIVE_PAT) ~= nil
  end
  return vim.startswith(p, "/")
end

---@param base string
---@param p string
---@return string
M.join = function(base, p)
  if M.is_absolute(lib.is_windows, p) or base == "" then
    return p
  end
  return vim.fs.joinpath(base, p)
end

---@param p string
---@return string
M.stem = function(p)
  return (string.gsub(vim.fs.basename(p), "(.)%.[^.]+$", "%1"))
end

---@param seps lib.Set<string>
---@param p string
---@return string? dir
---@return string rhs
M.split_at_last_sep = function(seps, p)
  for i = #p, 1, -1 do
    if seps[string.sub(p, i, i)] then
      return string.sub(p, 1, i), string.sub(p, i + 1)
    end
  end
  return nil, ""
end

return M
