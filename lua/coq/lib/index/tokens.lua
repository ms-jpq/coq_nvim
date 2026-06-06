local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buffers = require "coq.lib.buffers"
local set = require "coq.lib.set"

local M = {}

M.whitespace = set.new { string.byte " ", string.byte "\t", string.byte "\n", string.byte "\r" }

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

---@param spec string
---@return lib.Set<integer>
M.parse_charset = function(spec)
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

  return kw
end

---Yields each maximal keyword run, plus `<symbol_run><keyword_run>` when a
---non-whitespace non-keyword run immediately precedes a keyword run.
---Bare symbol runs (no following keyword) emit nothing.
---
---Example: tokenizing "bar @foo" yields "bar", "foo", "@foo".
---@param kw lib.Set<integer>
---@param text lib.Iterator<string>
---@return lib.Iterator<string>
M.keywords = function(kw, text)
  return async.wrap(function()
    local kw_acc = {}
    local sym_acc = {}
    local last_sym = nil

    local flush_kw = function()
      if next(kw_acc) then
        local s = table.concat(kw_acc)
        kw_acc = {}
        coroutine.yield(s)
        if last_sym then
          coroutine.yield(last_sym .. s)
        end
        last_sym = nil
      end
    end

    local commit_sym = function()
      if next(sym_acc) then
        last_sym = table.concat(sym_acc)
        sym_acc = {}
      end
    end

    for chunk in text do
      local i, n = 1, #chunk
      while i <= n do
        local b = string.byte(chunk, i)
        if kw[b] then
          commit_sym()
          local start = i
          while i <= n and kw[string.byte(chunk, i)] do
            i = i + 1
          end
          table.insert(kw_acc, string.sub(chunk, start, i - 1))
        elseif M.whitespace[b] then
          flush_kw()
          sym_acc = {}
          last_sym = nil
          i = i + 1
        else
          flush_kw()
          local start = i
          while i <= n do
            local b2 = string.byte(chunk, i)
            if kw[b2] or M.whitespace[b2] then
              break
            end
            i = i + 1
          end
          table.insert(sym_acc, string.sub(chunk, start, i - 1))
        end
      end
    end
    flush_kw()
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
M.trailing_symbol_before = function(kw, line)
  local i = #line
  while i > 0 do
    local b = string.byte(line, i)
    if kw[b] or M.whitespace[b] then
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
  atools.scheduled()
  return buffers.lines_around_cursor(ctx.buf)
end

---@param kw lib.Set<integer>
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
