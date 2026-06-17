local async = require "coq.lib.async"
local default_dict = require "coq.lib.default_dict"
local set = require "coq.lib.set"

local WS, SYM, KW = 0, 1, 2

local M = {}

M.WHITES = set.new { string.byte " ", string.byte "\t", string.byte "\n", string.byte "\r" }

local MB_WS_NBSP = "\xc2\xa0" -- U+00A0
local MB_WS_IDEOGRAPHIC = "\xe3\x80\x80" -- U+3000

---@param s string
---@return string
M._strip_mb_ws = function(s)
  s = string.gsub(s, MB_WS_NBSP, "  ")
  s = string.gsub(s, MB_WS_IDEOGRAPHIC, "   ")
  return s
end

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
  M.WS, M.SYM, M.KW = WS, SYM, KW
  local charset_cache = {}

  ---@param spec string
  ---@return table<integer, integer>
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

    local cls = {}
    for b = 0, 255 do
      cls[b] = kw[b] and KW or (M.WHITES[b] and WS or SYM)
    end

    charset_cache[spec] = cls
    return cls
  end
end

---@param cls table<integer, integer>  byte -> WS | SYM | KW (from parse_charset)
---@param text lib.Iterator<string>
---@return lib.Iterator<string>
M.keywords = function(cls, text)
  return async.wrap(function()
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
      chunk = M._strip_mb_ws(chunk)
      local i, n = 1, #chunk
      while i <= n do
        local kind = cls[string.byte(chunk, i)]
        local start = i
        while i <= n and cls[string.byte(chunk, i)] == kind do
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

---@param cls table<integer, integer>
---@param line string
---@return string
M.trailing_keyword_before = function(cls, line)
  line = M._strip_mb_ws(line)
  local i = #line
  while i > 0 and cls[string.byte(line, i)] == KW do
    i = i - 1
  end
  return string.sub(line, i + 1)
end

---@param cls table<integer, integer>
---@param line string
---@return string
M.match_prefix = function(cls, line)
  local k = M.trailing_keyword_before(cls, line)
  if k ~= "" then
    return k
  end
  return M.trailing_symbol_before(cls, line)
end

---@param cls table<integer, integer>
---@param line string
---@return string
M.trailing_symbol_before = function(cls, line)
  line = M._strip_mb_ws(line)
  local i = #line
  while i > 0 and cls[string.byte(line, i)] == SYM do
    i = i - 1
  end
  return string.sub(line, i + 1)
end

---@param cls table<integer, integer>
---@param line string
---@return string
M.leading_keyword = function(cls, line)
  line = M._strip_mb_ws(line)
  local i = 0
  while i < #line and cls[string.byte(line, i + 1)] == KW do
    i = i + 1
  end
  return string.sub(line, 1, i)
end

---@param cls table<integer, integer>
---@param text lib.Iterator<string>
---@return table<string, integer>
M.locality = function(cls, text)
  local acc = default_dict.new(function()
    return 0
  end)
  for word in M.keywords(cls, text) do
    acc[word] = acc[word] + 1
  end
  return acc --[[@as table<string, integer>]]
end

return M
