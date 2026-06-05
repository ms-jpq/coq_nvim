local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local buffers = require "coq.lib.buffers"
local index_m = require "coq.producers.buffers.index"
local lib = require "coq.lib"
local path_fmt = require "coq.producers.path_fmt"
local tokens = require "coq.lib.index.tokens"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class buffer.Meta
---@field tick integer
---@field lines? string[]
---@field filetype string
---@field filename string
---@field iskeyword string

local SOURCE = "buffers"
local MAX_BYTES = 1024 * 1024

local index_of = util.once(index_m.new)

local M = {}

---@param buf integer
---@param previous? buffer.Meta
---@return buffer.Meta?
M.buffer_meta = function(buf, previous)
  if not buffers.is_live(buf) then
    return nil
  end

  local tick = vim.b[buf].changedtick
  if previous and tick == previous.tick then
    return nil
  end

  return {
    tick = tick,
    filetype = vim.bo[buf].filetype,
    filename = vim.api.nvim_buf_get_name(buf),
    iskeyword = vim.bo[buf].iskeyword,
    lines = (vim.bo[buf].modified and buffers.buf_size(buf) <= MAX_BYTES) and buffers.lines_around_cursor(buf) or nil,
  }
end

---@type fun(settings: config.Settings): fun(idle_ctx: idle.Ctx)
local tracker_of = util.once(function(settings)
  return buf_tracker.new {
    compare = function(buf, previous)
      return worker.main(function(...)
        return require("coq.producers.buffers").buffer_meta(...)
      end, buf, previous)
    end,
    reindex = function(_, changes)
      lib.scope(function(defer)
        local close, stream = buf_tracker.merged(changes, function(_, curr)
          local kw = tokens.parse_charset(curr.iskeyword)
          return lib.scope(function(d)
            local text = (function()
              if curr.lines then
                return vim.iter { table.concat(curr.lines, "\n") }
              end
              local c, iter = atools.fs.scanfile(curr.filename)
              d(c)
              return iter
            end)()
            return vim.iter(tokens.keywords(kw, text --[[@as lib.Iterator<string>]])):totable()
          end)
        end)
        defer(close)

        for _, entry in stream do
          async.sleep(0)
          index_of(settings).prune { buf = entry.buf }
          if entry.data then
            for _, word in pairs(entry.data) do
              index_of(settings).insert {
                buf = entry.buf,
                word = word,
                filetype = entry.curr.filetype,
                filename = entry.curr.filename,
              }
            end
          end
        end
      end)
    end,
  }
end)

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker_of(settings)(idle_ctx)
end

---@param opts config.BuffersClient
---@param ctx ctx.full
---@param item buffer.Item
---@return lib.Iterator<string>
local doc_iter = function(opts, ctx, item)
  return coroutine.wrap(function()
    if not opts.same_filetype and item.filetype ~= "" then
      coroutine.yield(item.filetype .. opts.parent_scope)
    end
    if item.filename ~= "" then
      coroutine.yield(path_fmt.fmt(ctx.cwd, item.filename, ctx.filename))
    end
  end)
end

---@param settings config.Settings
M.matcher = util.batched(function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search {
    filetype = settings.clients.buffers.same_filetype and ctx.filetype or nil,
    keyword_before = ctx.keyword_before,
  }

  for hit in util.shape(settings, ctx, raw) do
    local item = util.item(settings, SOURCE, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = util.doc("", doc_iter(settings.clients.buffers, ctx, hit.item)),
    })
    if not coroutine.yield(item) then
      return
    end
  end
end)

M.new = util.threaded_module(SOURCE)

return M
