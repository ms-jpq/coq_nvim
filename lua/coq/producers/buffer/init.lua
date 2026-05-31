local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local fs = require "coq.producers.fs"
local index = require "coq.producers.buffer.index"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class buffer.BufInfo
---@field buf integer
---@field tick integer
---@field lines? string[]
---@field filetype string
---@field filename string
---@field iskeyword string

---@class buffer.State
---@field last_tick table<integer, integer>

local MAX_BYTES = 1024 * 1024

local M = {
  ---@type buffer.State
  state = { last_tick = {} },
}

---@param buf integer
---@return string[]
local buffer_lines = function(buf)
  local lo, hi = context.window_around_cursor(buf)
  return vim.api.nvim_buf_get_lines(buf, lo, hi, true)
end

---@param buf integer
---@param prev_tick? integer
---@return buffer.BufInfo?
M.buffer_info = function(buf, prev_tick)
  atools.scheduled()

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end

  local tick = vim.b[buf].changedtick
  if tick == prev_tick then
    return nil
  end

  local bytes = vim.api.nvim_buf_call(buf, function()
    return vim.fn.wordcount().bytes
  end)
  if bytes > MAX_BYTES then
    return nil
  end

  return {
    buf = buf,
    tick = tick,
    filetype = vim.bo[buf].filetype,
    filename = vim.api.nvim_buf_get_name(buf),
    iskeyword = vim.bo[buf].iskeyword,
    lines = vim.bo[buf].modified and buffer_lines(buf) or nil,
  }
end

---@param opts config.BuffersClient
---@param ctx ctx.full
---@param item buffer.Item
---@return lib.Iterator<string>
local doc_iter = function(opts, ctx, item)
  return async.wrap(function()
    if not opts.same_filetype and item.filetype ~= "" then
      coroutine.yield(item.filetype .. opts.parent_scope)
    end
    if item.filename ~= "" then
      coroutine.yield(fs.fmt_path(ctx.cwd, item.filename, ctx.filename))
    end
  end)
end

---@param buf integer
local update_buf = function(buf)
  local info = worker.main(function(...)
    return require("coq.producers.buffer").buffer_info(...)
  end, buf, M.state.last_tick[buf])
  if not info then
    return
  end

  M.state.last_tick[buf] = info.tick
  index.prune { buf = buf }

  local kw = tokens.parse_iskeyword(info.iskeyword)
  local lines = info.lines and vim.iter(info.lines) --[[@as lib.Iterator<string>]] or atools.file_lines(info.filename)

  for word in tokens.words(kw, lines) do
    index.insert {
      buf = buf,
      word = word,
      filetype = info.filetype,
      filename = info.filename,
    }
  end
end

M.idle = function(_, events)
  for buf, ev in pairs(events) do
    async.sleep(0)
    if ev.kind == "remove" then
      index.prune { buf = buf }
      M.state.last_tick[buf] = nil
    elseif ev.kind == "update" then
      update_buf(buf)
    end
  end
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.buffers
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]
  local search_ctx = {
    keyword_before = ctx.keyword_before,
    filetype = opts.same_filetype and ctx.filetype or nil,
  }

  local items = util.dedup(index.search(search_ctx) --[[@as lib.Iterator<buffer.Item>]], function(it)
    return it.word
  end)

  for item in items do
    if item.word ~= ctx.cword then
      local lines = vim.iter(doc_iter(opts, ctx, item)):totable()
      coroutine.yield {
        word = item.word,
        kind = "Text",
        menu = menu,
        meta = {
          filter = item.word,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
          doc = #lines > 0 and { lines = lines, filetype = "" } or nil,
        },
      }
    end
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return threaded.new {
    settings = settings,
    max_pulls = settings.clients.buffers.max_pulls,
    key = util.buffer_key,
    bind = util.buffer_bind,
    idle = function(...)
      require("coq.producers.buffer").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.buffer").matcher(...)
    end,
  }
end

return M
