local M = {}

local SEP = "/"
local NORM = { expand_env = false }
local HOME = vim.fs.normalize(vim.uv.os_homedir() or "", NORM)

---@param prefix string
---@param path string
---@return string?
local strip_prefix = function(prefix, path)
  if prefix == "" then
    return nil
  end

  local with_sep = string.sub(prefix, -1) == SEP and prefix or prefix .. SEP
  if path == prefix then
    return ""
  end

  if string.sub(path, 1, #with_sep) == with_sep then
    return string.sub(path, #with_sep + 1)
  end

  return nil
end

---@param cwd string
---@param path string
---@param current? string
---@return string
M.fmt_path = function(cwd, path, current)
  cwd = vim.fs.normalize(cwd, NORM)
  path = vim.fs.normalize(path, NORM)
  current = current and vim.fs.normalize(current, NORM) or nil

  if current and path == current then
    return "."
  end

  local rel = strip_prefix(cwd, path)
  if rel ~= nil then
    return rel == "" and "." or ("." .. SEP .. rel)
  end

  rel = strip_prefix(HOME, path)
  if rel ~= nil then
    return rel == "" and "~" or ("~" .. SEP .. rel)
  end

  return path
end

return M
