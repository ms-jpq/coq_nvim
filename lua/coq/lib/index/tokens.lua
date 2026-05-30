local async = require "coq.lib.async"

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
---@param lines fun(): string?
---@return fun(): string?
M.words = function(kw, lines)
  return async.wrap(function()
    for line in lines do
      local i, n = 1, #line
      while i <= n do
        local start = i
        while i <= n and kw[string.byte(line, i)] do
          i = i + 1
        end
        if i > start then
          coroutine.yield(string.sub(line, start, i - 1))
        else
          i = i + 1
        end
      end
    end
  end)
end

---@param ctx ctx.full
---@return string[]
M.surround = function(ctx)
  local half = math.floor(vim.api.nvim_win_get_height(ctx.win) / 2)
  local row = ctx.pos[1] - 1
  local lo = math.max(0, row - half)
  local hi = math.min(ctx.line_count, row + half + 1)

  return vim.api.nvim_buf_get_lines(ctx.buf, lo, hi, true)
end

---@param kw table<integer, true>
---@param lines fun(): string?
---@return table<string, integer>
M.locality = function(kw, lines)
  local acc = {}
  for word in M.words(kw, lines) do
    acc[word] = (acc[word] or 0) + 1
  end
  return acc
end

return M
