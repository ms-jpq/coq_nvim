local async = require "coq.lib.async"
local buffers = require "coq.lib.buffers"
local default_dict = require "coq.lib.default_dict"
local set = require "coq.lib.set"

local M = {}

M.WHITES = set.new { string.byte " ", string.byte "\t", string.byte "\n", string.byte "\r" }

M.MIN_LEN = 3

---@param s string
---@return integer
local decode = function(s)
  local n = tonumber(s)
  return n and math.floor(n) or string.byte(s)
end

---@param entry string
---@return [integer, integer][]
local ranges_of = function(entry)
  if entry == "" then
    return {}
  end

  if entry == "@" then
    return {
      { string.byte "A", string.byte "Z" },
      { string.byte "a", string.byte "z" },
      { 128, 255 },
    }
  end

  if entry == "@-@" then
    return { { string.byte "@", string.byte "@" } }
  end

  local lo, hi = string.match(entry, "^(.-)%-(.+)$")
  if lo and lo ~= "" then
    return {
      {
        decode(lo),
        decode(hi --[[@as string]]),
      },
    }
  end

  local b = decode(entry)
  return { { b, b } }
end

do
  local charset_cache = {}

  ---@param spec string
  ---@return lib.Set<integer>
  M.parse_charset = function(spec)
    local hit = charset_cache[spec]
    if hit then
      return hit
    end

    local kw = {}
    for entry in vim.gsplit(spec, ",", { plain = true }) do
      local exclude = string.sub(entry, 1, 1) == "^" and #entry > 1

      for _, range in pairs(ranges_of(exclude and string.sub(entry, 2) or entry)) do
        local lo, hi = unpack(range)
        for b = math.max(0, lo), math.min(255, hi) do
          kw[b] = not exclude or nil
        end
      end
    end

    charset_cache[spec] = kw
    return kw
  end
end

local KW, SYM, WS = 1, 2, 3

---@param kw lib.Set<integer>
---@param text lib.Iterator<string>
---@return lib.Iterator<string>
M.keywords = function(kw, text)
  return async.wrap(function()
    ---@param b integer
    ---@return integer
    local classify = function(b)
      if kw[b] then
        return KW
      elseif M.WHITES[b] then
        return WS
      else
        return SYM
      end
    end

    local pending_sym = nil

    ---@param kind integer
    ---@param run string
    local yield = function(kind, run)
      if kind == KW then
        if #run >= M.MIN_LEN then
          coroutine.yield(run)
        end
        if pending_sym then
          local joined = pending_sym .. run
          if #joined >= M.MIN_LEN then
            coroutine.yield(joined)
          end
        end
        pending_sym = nil
      elseif kind == SYM then
        pending_sym = run
      else
        pending_sym = nil
      end
    end

    local acc_kind, acc = nil, {}

    for chunk in text do
      local i, n = 1, #chunk
      while i <= n do
        local kind = classify(string.byte(chunk, i))
        local start = i
        while i <= n and classify(string.byte(chunk, i)) == kind do
          i = i + 1
        end
        local piece = string.sub(chunk, start, i - 1)

        if kind == acc_kind then
          table.insert(acc, piece)
        else
          if acc_kind then
            yield(acc_kind, table.concat(acc))
          end
          acc_kind, acc = kind, { piece }
        end
      end
    end

    if acc_kind then
      yield(acc_kind, table.concat(acc))
    end
  end)
end

---@param kw lib.Set<integer>
---@param line string
---@return string
M.trailing_keyword_before = function(kw, line)
  local i = #line
  while i > 0 and kw[string.byte(line, i)] do
    i = i - 1
  end
  return string.sub(line, i + 1)
end

---@param kw lib.Set<integer>
---@param line string
---@return string
M.match_prefix = function(kw, line)
  local k = M.trailing_keyword_before(kw, line)
  if k ~= "" then
    return k
  end
  return M.trailing_symbol_before(kw, line)
end

---@param kw lib.Set<integer>
---@param line string
---@return string
M.trailing_symbol_before = function(kw, line)
  local i = #line
  while i > 0 do
    local b = string.byte(line, i)
    if kw[b] or M.WHITES[b] then
      break
    end
    i = i - 1
  end
  return string.sub(line, i + 1)
end

---@param kw lib.Set<integer>
---@param line string
---@return string
M.leading_keyword = function(kw, line)
  local i = 0
  while i < #line and kw[string.byte(line, i + 1)] do
    i = i + 1
  end
  return string.sub(line, 1, i)
end

---@param ctx ctx.full
---@return string[]
M.surround = function(ctx)
  return buffers.lines_around_cursor(ctx.buf)
end

---@param kw lib.Set<integer>
---@param text lib.Iterator<string>
---@return table<string, integer>
M.locality = function(kw, text)
  local acc = default_dict.new(function()
    return 0
  end)
  for word in M.keywords(kw, text) do
    acc[word] = acc[word] + 1
  end
  return acc --[[@as table<string, integer>]]
end

return M
