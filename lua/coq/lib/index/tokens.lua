local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"

local M = {}

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
    return { { 65, 90 }, { 97, 122 }, { 128, 255 } }
  end

  if entry == "@-@" then
    return { { 64, 64 } }
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

---@param iskeyword string
---@return table<integer, true>
M.parse_iskeyword = function(iskeyword)
  local kw = {}

  for entry in vim.gsplit(iskeyword, ",", { plain = true }) do
    local exclude = string.sub(entry, 1, 1) == "^" and #entry > 1

    for _, range in pairs(ranges_of(exclude and string.sub(entry, 2) or entry)) do
      local lo, hi = unpack(range)
      for b = math.max(0, lo), math.min(255, hi) do
        kw[b] = not exclude or nil
      end
    end
  end

  return kw
end

---@param kw table<integer, true>
---@param text lib.Iterator<string>
---@return lib.Iterator<string>
M.keywords = function(kw, text)
  return async.wrap(function()
    local acc = {}
    local flush = function()
      if next(acc) then
        coroutine.yield(table.concat(acc))
        acc = {}
      end
    end

    for chunk in text do
      local i, n = 1, #chunk
      while i <= n do
        local start = i
        while i <= n and kw[string.byte(chunk, i)] do
          i = i + 1
        end
        if i > start then
          table.insert(acc, string.sub(chunk, start, i - 1))
        end
        if i <= n then
          flush()
          i = i + 1
        end
      end
    end
    flush()
  end)
end

---@param kw table<integer, true>
---@param line string
---@return string
M.trailing_keyword_before = function(kw, line)
  local i = #line
  while i > 0 and kw[string.byte(line, i)] do
    i = i - 1
  end
  return string.sub(line, i + 1)
end

---@param ctx ctx.full
---@return string[]
M.surround = function(ctx)
  atools.scheduled()
  local lo, hi = context.window_around_cursor(ctx.buf)
  return vim.api.nvim_buf_get_lines(ctx.buf, lo, hi, true)
end

---@param kw table<integer, true>
---@param text lib.Iterator<string>
---@return table<string, integer>
M.locality = function(kw, text)
  local acc = {}
  for word in M.keywords(kw, text) do
    acc[word] = (acc[word] or 0) + 1
  end
  return acc
end

return M
