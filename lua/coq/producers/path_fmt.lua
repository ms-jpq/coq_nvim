local lib = require "coq.lib"

local M = {}

local HOME = vim.uv.os_homedir() or ""

---@param is_windows boolean
---@param prefix string
---@param path string
---@return string?
local strip_prefix = function(is_windows, prefix, path)
  if prefix == "" then
    return nil
  end

  local sep = is_windows and "\\" or "/"
  local eq = is_windows and function(a, b)
    return string.lower(a) == string.lower(b)
  end or function(a, b)
    return a == b
  end

  local with_sep = string.sub(prefix, -1) == sep and prefix or prefix .. sep
  if eq(path, prefix) then
    return ""
  end

  if eq(string.sub(path, 1, #with_sep), with_sep) then
    return string.sub(path, #with_sep + 1)
  end

  return nil
end

---@param cwd string
---@param path string
---@param current? string
---@param is_windows? boolean
---@return string
M.fmt = function(cwd, path, current, is_windows)
  if is_windows == nil then
    is_windows = lib.is_windows
  end

  local sep = is_windows and "\\" or "/"
  local opts = { expand_env = false, win = is_windows }
  local norm = function(s)
    local n = vim.fs.normalize(s, opts)
    return is_windows and (string.gsub(n, "/", "\\")) or n
  end

  cwd = norm(cwd)
  path = norm(path)
  current = current and norm(current) or nil
  local home = norm(HOME)

  if current and path == current then
    return "."
  end

  local rel = strip_prefix(is_windows, cwd, path)
  if rel ~= nil then
    return rel == "" and "." or ("." .. sep .. rel)
  end

  rel = strip_prefix(is_windows, home, path)
  if rel ~= nil then
    return rel == "" and "~" or ("~" .. sep .. rel)
  end

  return path
end

return M
