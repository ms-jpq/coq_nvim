local M = {}

local SEP = "/"
local HOME = vim.uv.os_homedir() or ""

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
---@param windows? boolean
---@return string
M.fmt_path = function(cwd, path, current, windows)
  local opts = { expand_env = false, win = windows }

  cwd = vim.fs.normalize(cwd, opts)
  path = vim.fs.normalize(path, opts)
  current = current and vim.fs.normalize(current, opts) or nil
  local home = vim.fs.normalize(HOME, opts)

  if current and path == current then
    return "."
  end

  local rel = strip_prefix(cwd, path)
  if rel ~= nil then
    return rel == "" and "." or ("." .. SEP .. rel)
  end

  rel = strip_prefix(home, path)
  if rel ~= nil then
    return rel == "" and "~" or ("~" .. SEP .. rel)
  end

  return path
end

return M
