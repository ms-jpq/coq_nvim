local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local closable = require "coq.lib.closable"
local errs = require "coq.lib.errs"
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
  local row, b, u16, u32 = unpack(ctx.pos)
  return {
    uid = next_uid(),
    pos = { row - 1, b, u16, u32 },
    line = ctx.line,
  }
end

---@param settings config.Settings
---@param ctx ctx.full
---@param raw lsp.CompletionItem
---@param encoding string
---@return completions.Item
local item_of = function(settings, ctx, raw, encoding)
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
    lsp = {
      item = raw,
      position_encoding = encoding,
    },
  })
end

---@param settings config.Settings
---@param ctx ctx.full
---@param entry third_party.Source
---@param arg third_party.Args
---@return fun() close
---@return lib.Iterator<completions.Item[]> iter
local query_one = function(settings, ctx, entry, arg)
  return closable.iter(function(_)
    local ok, result = cancel.pcall(async.awaitify(entry.fn), arg)
    if not ok then
      errs.report(result)
      return
    end

    if type(result) ~= "table" or type(result.items) ~= "table" then
      return
    end

    local encoding = entry.offset_encoding or "utf-16"
    local batch = vim
      .iter(result.items)
      :map(function(raw)
        return item_of(settings, ctx, raw, encoding)
      end)
      :totable()
    if #batch > 0 then
      coroutine.yield(batch)
    end
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
        if util.skip_empty(ctx) then
          return
        end

        local arg = args_of(ctx)

        ---@type table<any, third_party.Source>
        ---@diagnostic disable-next-line: undefined-field
        local sources = _G.COQsources or {}

        local iters = {}
        for _, entry in pairs(sources) do
          if type(entry) == "table" and type(entry.fn) == "function" then
            local c, i = query_one(settings, ctx, entry, arg)
            defer(c)
            table.insert(iters, i)
          end
        end

        if #iters == 0 then
          return
        end

        local close, merged = async.merge(iters)
        defer(close)

        for _, batch in merged do
          coroutine.yield(batch)
        end
      end)
    end,
  }
end

return M
