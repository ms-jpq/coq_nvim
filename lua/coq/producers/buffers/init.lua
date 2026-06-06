local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local buffers = require "coq.lib.buffers"
local index_m = require "coq.producers.buffers.index"
local itertools = require "coq.lib.itertools"
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

local index_of = util.once(index_m.new)

local M = {}

---@param max_bytes integer
---@param buf integer
---@param previous? buffer.Meta
---@return buffer.Meta?
M.buffer_meta = function(max_bytes, buf, previous)
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
    lines = (vim.bo[buf].modified and buffers.buf_size(buf) <= max_bytes) and buffers.lines_around_cursor(buf) or nil,
  }
end

---@type fun(settings: config.Settings): fun(idle_ctx: idle.Ctx)
local tracker_of = util.once(function(settings)
  return buf_tracker.new {
    compare = function(buf, previous)
      return worker.main(function(...)
        return require("coq.producers.buffers").buffer_meta(...)
      end, settings.clients.buffers.max_bytes, buf, previous)
    end,
    reindex = function(_, changes)
      for buf, change in pairs(changes) do
        async.sleep(0)
        local _, _, curr = unpack(change)

        index_of(settings).prune { buf = buf }
        if curr ~= nil then
          lib.scope(function(d)
            local words = (function()
              if curr.lines then
                return itertools.intersperse("\n", vim.iter(curr.lines) --[[@as lib.Iterator<string>]])
              end
              local c, iter = atools.fs.scanfile(curr.filename)
              d(c)
              return iter
            end)()

            local kw = tokens.parse_charset(curr.iskeyword)
            for i, word in vim.iter(tokens.keywords(kw, words)):enumerate() do
              index_of(settings).insert {
                buf = buf,
                word = word,
                filetype = curr.filetype,
                filename = curr.filename,
              }
              if i % util.BATCH == 0 then
                async.sleep(0)
              end
            end
          end)
        end
      end
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
    match_before = ctx.match_before,
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
