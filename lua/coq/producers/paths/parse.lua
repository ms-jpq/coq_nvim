local path = require "coq.lib.path"
local tokens = require "coq.lib.index.tokens"

local M = {}

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
  local separators = path.seps(opts.is_windows)
  local token = tokens.trailing_keyword_before(opts.isfname, line_before)
  if token == "" then
    return nil
  end

  local expanded = M._expand_head(opts.is_windows, opts.home, opts.env, token, separators)
  local resolved, partial = path.split_at_last_sep(separators, expanded)
  if not resolved then
    return nil
  end

  local literal = string.sub(token, 1, #token - #partial)
  return {
    resolved_directory = resolved,
    literal_directory = literal,
    local_sep = string.sub(literal, -1),
    partial = partial,
    absolute = path.is_absolute(opts.is_windows, resolved),
    start = #line_before - #token,
  }
end

return M
