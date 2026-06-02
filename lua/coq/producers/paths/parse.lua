local async = require "coq.lib.async"
local lib = require "coq.lib"

local DRIVE_PAT = "^%a:[/\\]"

local M = {}

---@param is_windows boolean
---@return table<string, true>
local seps = function(is_windows)
  return is_windows and { ["/"] = true, ["\\"] = true } or { ["/"] = true }
end

---@param is_windows boolean
---@return lib.Iterator<string>
local patterns = function(is_windows)
  local pats = async.wrap(function()
    coroutine.yield "%.%."
    coroutine.yield "%."
    coroutine.yield "~"

    if is_windows then
      coroutine.yield "%a:"
      coroutine.yield "%%[%w_]+%%"
    end

    coroutine.yield "%$[%w_]+"
    coroutine.yield "%${[%w_]+}"
    coroutine.yield "@[%w%.%-_+]+"

    coroutine.yield ""
  end)

  return async.wrap(function()
    for sep in pairs(seps(is_windows)) do
      for pattern in pats do
        coroutine.yield("()" .. pattern .. sep)
      end
    end
  end)
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
  local sep_set = seps(is_windows)
  for i = #path, 1, -1 do
    if sep_set[string.sub(path, i, i)] then
      return string.sub(path, 1, i), string.sub(path, i + 1)
    end
  end
  return nil, ""
end

---@param is_windows boolean
---@param line_before string
---@return fun(): integer?, string?
local find_starts = function(is_windows, line_before)
  return async.wrap(function()
    local seen, positions = {}, {}
    for pat in patterns(is_windows) do
      local init = 1
      while init <= #line_before do
        local s, _, pos = string.find(line_before, pat, init)
        if not s then
          break
        end
        if not seen[pos] then
          seen[pos] = true
          table.insert(positions, pos)
        end
        init = s + 1
      end
    end
    table.sort(positions)

    for _, p in ipairs(positions) do
      coroutine.yield(p, string.sub(line_before, p))
    end
  end)
end

---@class paths.parse.Candidate
---@field directory string
---@field partial   string
---@field absolute  boolean
---@field start     integer

---@class paths.parse.Opts
---@field is_windows? boolean
---@field env?        table<string, string>
---@field home?       string

---@param line_before string
---@param opts? paths.parse.Opts
---@return lib.Iterator<paths.parse.Candidate>
M.candidates = function(line_before, opts)
  opts = opts or {}
  local is_windows = opts.is_windows
  if is_windows == nil then
    is_windows = lib.is_windows
  end
  local env = opts.env or vim.uv.os_environ()
  local home = opts.home or vim.uv.os_homedir() or ""

  return async.wrap(function()
    for pos, token in find_starts(is_windows, line_before) do
      local expanded = expand_head(is_windows, home, env, token)
      local dir, partial = split_at_last_sep(is_windows, expanded)
      if dir then
        coroutine.yield {
          directory = dir,
          partial = partial,
          absolute = is_absolute(is_windows, dir),
          start = pos - 1,
        }
      end
    end
  end)
end

M._internal = {
  seps = seps,
  patterns = patterns,
  find_starts = find_starts,
  expand_env = expand_env,
  expand_head = expand_head,
  is_absolute = is_absolute,
  split_at_last_sep = split_at_last_sep,
}

return M
