local set = require "coq.lib.set"

local DRIVE_PAT = "^%a:[/\\]"

local M = {}

---@param is_windows boolean
---@param path_seps string[]
---@return lib.Set<string>
M._seps = function(is_windows, path_seps)
  local seps = set.new(is_windows and { "/", "\\" } or { "/" })

  local filtered = {}
  for _, s in pairs(path_seps) do
    if seps[s] then
      table.insert(filtered, s)
    end
  end

  return #filtered > 0 and set.new(filtered) or seps
end

---@param is_windows boolean
---@param separators lib.Set<string>
---@return lib.Iterator<string>
M._patterns = function(is_windows, separators)
  local heads = function()
    return coroutine.wrap(function()
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
  end

  return coroutine.wrap(function()
    for sep in pairs(separators) do
      for pattern in heads() do
        coroutine.yield("()" .. pattern .. sep)
      end
    end
  end)
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

---@param is_windows boolean
---@param separators lib.Set<string>
---@param line_before string
---@return fun(): integer?, string?
M._find_starts = function(is_windows, separators, line_before)
  return coroutine.wrap(function()
    local seen, positions = {}, {}
    for pat in M._patterns(is_windows, separators) do
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
---@field path_seps  string[]

---@param line_before string
---@param opts paths.parse.Opts
---@return lib.Iterator<paths.parse.Candidate>
M.candidates = function(line_before, opts)
  local is_windows = opts.is_windows
  local env = opts.env
  local home = opts.home
  local separators = M._seps(is_windows, opts.path_seps)

  return coroutine.wrap(function()
    for pos, token in M._find_starts(is_windows, separators, line_before) do
      local expanded = M._expand_head(is_windows, home, env, token, separators)
      local resolved, partial = M._split_at_last_sep(separators, expanded)

      if resolved then
        local literal = string.sub(token, 1, #token - #partial)
        coroutine.yield {
          resolved_directory = resolved,
          literal_directory = literal,
          local_sep = string.sub(literal, -1),
          partial = partial,
          absolute = M._is_absolute(is_windows, separators, resolved),
          start = pos - 1,
        }
      end
    end
  end)
end

return M
