local lib = require "coq.lib"

local DRIVE_PAT = "^%a:[/\\]"

local M = {}

---@param is_windows boolean
---@return table<string, true>
local seps = function(is_windows)
  return is_windows and { ["/"] = true, ["\\"] = true } or { ["/"] = true }
end

-- Lua patterns matching a recognized path-head followed by a sep. Each pattern
-- uses `()` to capture the 1-based position where the head starts. Found via
-- string.find / string.match.
---@param is_windows boolean
---@return string[]
local patterns = function(is_windows)
  if is_windows then
    return {
      "()~[/\\]",
      "()%.%.[/\\]",
      "()%.[/\\]",
      "()%${[%w_]+}[/\\]",
      "()%$[%w_]+[/\\]",
      "()%%[%w_]+%%[/\\]",
      "()%a:[/\\]",
      "()[/\\]",
      "()[%w%.%-_+]+[/\\]",
    }
  end
  return {
    "()~/",
    "()%.%./",
    "()%./",
    "()%${[%w_]+}/",
    "()%$[%w_]+/",
    "()/",
    "()[%w%.%-_+]+/",
  }
end

---@param is_windows boolean
---@return string
local interior_chars = function(is_windows)
  return is_windows and "%w%.%-_+/\\" or "%w%.%-_+/"
end

---@param is_windows boolean
---@param token string
---@return boolean
local is_path_shaped = function(is_windows, token)
  if token == "" then
    return false
  end

  for sep in pairs(seps(is_windows)) do
    if string.find(token, sep, 1, true) then
      return true
    end
  end

  local c1 = string.sub(token, 1, 1)
  if c1 == "~" or c1 == "$" then
    return true
  end

  if is_windows then
    if c1 == "%" then
      return true
    end
    if string.match(token, DRIVE_PAT) then
      return true
    end
  end

  return token == "." or token == ".."
end

---@param is_windows boolean
---@param env table<string, string>
---@param token string
---@return string
local expand_env = function(is_windows, env, token)
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
---@param home string
---@param env table<string, string>
---@param token string
---@return string
local expand_head = function(is_windows, home, env, token)
  local c1 = string.sub(token, 1, 1)
  if c1 == "~" then
    local rest = string.sub(token, 2)
    local after_tilde = string.sub(rest, 1, 1)
    if rest == "" or seps(is_windows)[after_tilde] then
      return home .. rest
    end
  end
  return expand_env(is_windows, env, token)
end

---@param is_windows boolean
---@param path string
---@return boolean
local is_absolute = function(is_windows, path)
  local c1 = string.sub(path, 1, 1)
  if seps(is_windows)[c1] then
    return true
  end
  return is_windows and string.match(path, DRIVE_PAT) ~= nil
end

---@param is_windows boolean
---@param path string
---@return string? dir
---@return string rhs
local split_at_last_sep = function(is_windows, path)
  local seps = seps(is_windows)
  for i = #path, 1, -1 do
    if seps[string.sub(path, i, i)] then
      return string.sub(path, 1, i), string.sub(path, i + 1)
    end
  end
  return nil, ""
end

---@class paths.parse.Candidate
---@field segment_start integer
---@field rhs           string
---@field dir_resolved  string
---@field is_absolute   boolean

---@class paths.parse.Opts
---@field is_windows? boolean
---@field env?        table<string, string>
---@field home?       string

---@param line_before string
---@param opts? paths.parse.Opts
---@return paths.parse.Candidate[]
M.candidates = function(line_before, opts)
  opts = opts or {}
  local is_windows = opts.is_windows
  if is_windows == nil then
    is_windows = lib.is_windows
  end
  local env = opts.env or vim.uv.os_environ()
  local home = opts.home or vim.uv.os_homedir() or ""

  local tail_pat = "^[" .. interior_chars(is_windows) .. "]*$"

  local seen, starts = {}, {}
  for _, pat in ipairs(patterns(is_windows)) do
    local init = 1
    while init <= #line_before do
      local s, e, pos = string.find(line_before, pat, init)
      if not s then
        break
      end
      local tail = string.sub(line_before, e + 1)
      if string.match(tail, tail_pat) and not seen[pos] then
        seen[pos] = true
        table.insert(starts, pos)
      end
      init = s + 1
    end
  end

  table.sort(starts)

  local out = {}
  for _, p in ipairs(starts) do
    local token = string.sub(line_before, p)
    local expanded = expand_head(is_windows, home, env, token)
    local dir, rhs = split_at_last_sep(is_windows, expanded)
    if dir then
      table.insert(out, {
        segment_start = p - 1,
        rhs = rhs,
        dir_resolved = dir,
        is_absolute = is_absolute(is_windows, dir),
      })
    end
  end
  return out
end

M._internal = {
  seps = seps,
  patterns = patterns,
  interior_chars = interior_chars,
  is_path_shape = is_path_shaped,
  expand_env = expand_env,
  expand_head = expand_head,
  is_absolute = is_absolute,
  split_at_last_sep = split_at_last_sep,
}

return M
