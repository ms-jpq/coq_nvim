local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"
local match = require "coq.lib.index.rank.match"
local util = require "coq.producers.util"

local SOURCE = "third_party"

---@class third_party.Source
---@field name string
---@field fn fun(args: third_party.Args, callback: fun(result: third_party.Result))
---@field offset_encoding? "utf-8"|"utf-16"|"utf-32"

---@class third_party.Args
---@field uid integer
---@field pos [integer, integer, integer, integer]
---@field line string

---@class third_party.Result
---@field isIncomplete? boolean
---@field items lsp.CompletionItem[]

local next_uid = (function()
  local n = 0
  return function()
    n = n + 1
    return n
  end
end)()

---@param ctx ctx.full
---@return third_party.Args
local args_of = function(ctx)
  local row, col = unpack(ctx.pos)
  return {
    uid = next_uid(),
    pos = {
      row - 1,
      col,
      vim.str_utfindex(ctx.line, "utf-16", col, true),
      vim.str_utfindex(ctx.line, "utf-32", col, true),
    },
    line = ctx.line,
  }
end

---@param settings config.Settings
---@param ctx ctx.full
---@param raw lsp.CompletionItem
---@return completions.Item
local item_of = function(settings, ctx, raw)
  local label = raw.label or ""
  local insert_text = raw.insertText or label
  local is_snippet = raw.insertTextFormat == 2
  local filter = raw.filterText or label
  local kind = vim.lsp.protocol.CompletionItemKind[raw.kind] or ""
  return util.item(settings, SOURCE, {
    word = is_snippet and label or insert_text,
    abbr = label,
    kind = kind,
    filter = filter,
    fuzzy = match.score(ctx.keyword_before, filter),
    snippet = is_snippet and insert_text or nil,
  })
end

---@param settings config.Settings
---@param ctx ctx.full
---@param entry third_party.Source
---@return fun() close
---@return lib.Iterator<completions.Item[]> iter
local query_one = function(settings, ctx, entry)
  return closable.iter(function(_)
    local result = async.awaitify(entry.fn)(args_of(ctx))
    if type(result) ~= "table" or type(result.items) ~= "table" then
      return
    end
    local batch = vim
      .iter(result.items)
      :map(function(raw)
        return item_of(settings, ctx, raw)
      end)
      :totable()
    coroutine.yield(batch)
  end)
end

local M = {}

---@return producers.Producer<ctx.full>
M.new = function()
  return {
    source = SOURCE,
    idle = lib.noop,
    search = function(settings, ctx)
      return closable.iter(function(defer)
        ---@type table<any, third_party.Source>
        ---@diagnostic disable-next-line: undefined-field
        local sources = _G.COQsources or {}
        local iters = {}
        local closes = {}
        for _, entry in pairs(sources) do
          if type(entry) == "table" and type(entry.fn) == "function" then
            local c, i = query_one(settings, ctx, entry)
            table.insert(closes, c)
            table.insert(iters, i)
          end
        end

        if #iters == 0 then
          return
        end

        local close, merged = async.merge(iters)
        defer(close)
        for _, c in pairs(closes) do
          defer(c)
        end

        for _, batch in merged do
          coroutine.yield(batch)
        end
      end)
    end,
  }
end

return M
