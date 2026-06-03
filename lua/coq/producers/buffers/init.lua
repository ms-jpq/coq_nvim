local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local context = require "coq.lib.context"
local path_fmt = require "coq.producers.path_fmt"
local index_m = require "coq.producers.buffers.index"
local lib = require "coq.lib"
local producer = require "coq.lib.producers"
local tokens = require "coq.lib.index.tokens"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class buffer.Meta : buf_tracker.Meta
---@field buf integer
---@field lines? string[]
---@field filetype string
---@field filename string
---@field iskeyword string

local MAX_BYTES = 1024 * 1024

local index = util.once(index_m.new)

local M = {}

---@param buf integer
---@return string[]
local buffer_lines = function(buf)
  local lo, hi = context.window_around_cursor(buf)
  return vim.api.nvim_buf_get_lines(buf, lo, hi, true)
end

---@param buf integer
---@param prev_tick? integer
---@return buffer.Meta?
M.buffer_meta = function(buf, prev_tick)
  atools.scheduled()

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end

  local tick = vim.b[buf].changedtick
  if tick == prev_tick then
    return nil
  end

  return {
    buf = buf,
    tick = tick,
    filetype = vim.bo[buf].filetype,
    filename = vim.api.nvim_buf_get_name(buf),
    iskeyword = vim.bo[buf].iskeyword,
    lines = (vim.bo[buf].modified and vim.api.nvim_buf_call(buf, function()
      return vim.fn.wordcount().bytes
    end) <= MAX_BYTES) and buffer_lines(buf) or nil,
  }
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

local tracker = buf_tracker.new {
  fetch = function(buf, prev_tick)
    return worker.main(function(...)
      return require("coq.producers.buffers").buffer_meta(...)
    end, buf, prev_tick)
  end,
  reindex = function(settings, metas)
    for _, meta in pairs(metas) do
      async.sleep(0)
      local kw = tokens.parse_iskeyword(meta.iskeyword)

      lib.scope(function(defer)
        local text = (function()
          if meta.lines then
            return vim.iter { table.concat(meta.lines, "\n") }
          end
          local close, iter = atools.fs.scanfile(meta.filename)
          defer(close)
          return iter
        end)()

        for word in
          tokens.keywords(kw, text --[[@as lib.Iterator<string>]])
        do
          index(settings).insert {
            buf = meta.buf,
            word = word,
            filetype = meta.filetype,
            filename = meta.filename,
          }
        end
      end)
    end
  end,
  prune = function(settings, buf)
    index(settings).prune { buf = buf }
  end,
}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker(settings, idle_ctx)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.buffers

  local raw = index(settings).search {
    filetype = opts.same_filetype and ctx.filetype or nil,
    keyword_before = ctx.keyword_before,
  }
  local shaped = util.shape(settings, ctx, raw)

  for hit in shaped do
    local lines = vim.iter(doc_iter(opts, ctx, hit.item)):totable()

    coroutine.yield(util.item(settings, opts, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = #lines > 0 and { lines = lines, filetype = "" } or nil,
    }))
  end
end

---@return producers.Producer<ctx.full>
M.new = function()
  return producer.threaded {
    idle = function(...)
      require("coq.producers.buffers").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.buffers").matcher(...)
    end,
  }
end

return M
