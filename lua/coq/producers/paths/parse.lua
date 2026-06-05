local set = require "coq.lib.set"
local tokens = require "coq.lib.index.tokens"

local DRIVE_PAT = "^%a:[/\\]"

local M = {}

---@param is_windows boolean
---@return lib.Set<string>
M._seps = function(is_windows)
  return set.new(is_windows and { "/", "\\" } or { "/" })
end

---@param is_windows boolean
---@param env table<string, string>
---@param token string
---@return string
M._expand_env = function(is_windows, env, token)
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
---@param separators lib.Set<string>
---@return string
M._expand_head = function(is_windows, home, env, token, separators)
  local c1 = string.sub(token, 1, 1)
  if c1 == "~" then
    local rest = string.sub(token, 2)
    local after_tilde = string.sub(rest, 1, 1)
    if rest == "" or separators[after_tilde] then
      return home .. rest
    end
  end
  return M._expand_env(is_windows, env, token)
end

---@param is_windows boolean
---@param separators lib.Set<string>
---@param path string
---@return boolean
M._is_absolute = function(is_windows, separators, path)
  local c1 = string.sub(path, 1, 1)
  if separators[c1] then
    return true
  end
  return is_windows and string.match(path, DRIVE_PAT) ~= nil
end

---@param separators lib.Set<string>
---@param path string
---@return string? dir
---@return string rhs
M._split_at_last_sep = function(separators, path)
  for i = #path, 1, -1 do
    if separators[string.sub(path, i, i)] then
      return string.sub(path, 1, i), string.sub(path, i + 1)
    end
  end
  return nil, ""
end

---@class paths.parse.Candidate
---@field resolved_directory string
---@field literal_directory  string
---@field local_sep          string
---@field partial            string
---@field absolute           boolean
---@field start              integer

---@class paths.parse.Opts
---@field is_windows boolean
---@field env        table<string, string>
---@field home       string
---@field isfname    lib.Set<integer>

---@param line_before string
---@param opts paths.parse.Opts
---@return paths.parse.Candidate?
M.candidate = function(line_before, opts)
  local separators = M._seps(opts.is_windows)
  local token = tokens.trailing_keyword_before(opts.isfname, line_before)
  if token == "" then
    return nil
  end

  local expanded = M._expand_head(opts.is_windows, opts.home, opts.env, token, separators)
  local resolved, partial = M._split_at_last_sep(separators, expanded)
  if not resolved then
    return nil
  end

  local literal = string.sub(token, 1, #token - #partial)
  return {
    resolved_directory = resolved,
    literal_directory = literal,
    local_sep = string.sub(literal, -1),
    partial = partial,
    absolute = M._is_absolute(opts.is_windows, separators, resolved),
    start = #line_before - #token,
  }
end

return M
