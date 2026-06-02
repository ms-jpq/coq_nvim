local lib = require "coq.lib"

local DRIVE_PAT = "^%a:"

local M = {}

---@param is_windows boolean
---@return table<string, true>
local default_seps = function(is_windows)
  return is_windows and { ["/"] = true, ["\\"] = true } or { ["/"] = true }
end

---@param is_windows boolean
---@param token string
---@return boolean
local is_path_shape = function(is_windows, token)
  if token == "" then
    return false
  end
  if string.find(token, "/", 1, true) then
    return true
  end
  if is_windows and string.find(token, "\\", 1, true) then
    return true
  end
  local c1 = string.sub(token, 1, 1)
  if c1 == "~" or c1 == "/" or c1 == "$" then
    return true
  end
  if is_windows then
    if c1 == "\\" or c1 == "%" then
      return true
    end
    if string.match(token, DRIVE_PAT) then
      return true
    end
  end
  if token == "." or token == ".." then
    return true
  end
  return false
end

---@param is_windows boolean
---@param token string
---@param env table<string, string>
---@param home string
---@return string
local expand_head = function(is_windows, token, env, home)
  if string.sub(token, 1, 1) == "~" then
    local rest = string.sub(token, 2)
    local c = string.sub(rest, 1, 1)
    if rest == "" or c == "/" or (is_windows and c == "\\") then
      return home .. rest
    end
  end

  local braced, b_rest = string.match(token, "^%${([%w_]+)}(.*)")
  if braced and env[braced] then
    return env[braced] .. b_rest
  end

  local dollar, d_rest = string.match(token, "^%$([%w_]+)(.*)")
  if dollar and env[dollar] then
    return env[dollar] .. d_rest
  end

  if is_windows then
    local pct, p_rest = string.match(token, "^%%([%w_]+)%%(.*)")
    if pct and env[pct] then
      return env[pct] .. p_rest
    end
  end

  return token
end

---@param is_windows boolean
---@param path string
---@return boolean
local is_absolute = function(is_windows, path)
  local c = string.sub(path, 1, 1)
  if c == "/" then
    return true
  end
  if is_windows then
    if c == "\\" then
      return true
    end
    if string.match(path, DRIVE_PAT) then
      return true
    end
  end
  return false
end

---@param path string
---@param seps table<string, true>
---@return string dir  -- includes trailing sep, or "" if none
---@return string rhs  -- after the last sep
local split_at_last_sep = function(path, seps)
  for i = #path, 1, -1 do
    if seps[string.sub(path, i, i)] then
      return string.sub(path, 1, i), string.sub(path, i + 1)
    end
  end
  return "", path
end

---@class paths.fs.Parsed
---@field segment_start integer
---@field rhs           string
---@field dir_resolved  string
---@field is_absolute   boolean

---@class paths.fs.Opts
---@field is_windows? boolean
---@field seps?       table<string, true>
---@field env?        table<string, string>
---@field home?       string

---@param line_before string
---@param opts? paths.fs.Opts
---@return paths.fs.Parsed?
M.parse = function(line_before, opts)
  opts = opts or {}
  local is_windows = opts.is_windows
  if is_windows == nil then
    is_windows = lib.is_windows
  end
  local seps = opts.seps or default_seps(is_windows)
  local env = opts.env or vim.uv.os_environ()
  local home = opts.home or env.HOME or env.USERPROFILE or ""

  local token = line_before
  if not is_path_shape(is_windows, token) then
    return nil
  end

  local expanded = expand_head(is_windows, token, env, home)
  local dir, rhs = split_at_last_sep(expanded, seps)
  if dir == "" then
    return nil
  end

  return {
    segment_start = 0,
    rhs = rhs,
    dir_resolved = dir,
    is_absolute = is_absolute(is_windows, dir),
  }
end

M._internal = {
  default_seps = default_seps,
  is_path_shape = is_path_shape,
  expand_head = expand_head,
  is_absolute = is_absolute,
  split_at_last_sep = split_at_last_sep,
}

return M
