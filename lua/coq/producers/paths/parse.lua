local path = require "coq.lib.path"

local M = {}

M.ANCHOR = {
  abs = "abs",
  cwd = "cwd",
  both = "both",
}

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
      coroutine.yield "@"

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
  if c1 == "@" then
    return string.sub(token, 2)
  end
  return M._expand_env(is_windows, env, token)
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

---@alias paths.parse.Anchor "abs" | "cwd" | "both"

---@class paths.parse.Candidate
---@field resolved_directory string
---@field literal_directory  string
---@field local_sep          string
---@field partial            string
---@field anchor             paths.parse.Anchor
---@field start              integer

---@class paths.parse.Opts
---@field is_windows boolean
---@field env        table<string, string>
---@field home       string

---@param line_before string
---@param opts paths.parse.Opts
---@return lib.Iterator<paths.parse.Candidate>
M.candidates = function(line_before, opts)
  local separators = path.seps(opts.is_windows)

  return coroutine.wrap(function()
    for pos, token in M._find_starts(opts.is_windows, separators, line_before) do
      local expanded = M._expand_head(opts.is_windows, opts.home, opts.env, token, separators)
      local resolved, partial = path.split_at_last_sep(separators, expanded)

      if resolved then
        local literal = string.sub(token, 1, #token - #partial)
        local anchor = (string.sub(token, 1, 1) == "@" and M.ANCHOR.cwd)
          or (path.is_absolute(opts.is_windows, resolved) and M.ANCHOR.abs)
          or M.ANCHOR.both

        coroutine.yield {
          resolved_directory = resolved,
          literal_directory = literal,
          local_sep = string.sub(literal, -1),
          partial = partial,
          anchor = anchor,
          start = pos - 1,
        }
      end
    end
  end)
end

return M
