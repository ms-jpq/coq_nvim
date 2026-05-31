local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local fs = require "coq.producers.fs"
local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"
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

local kinds = {
  BufEnter = "update",
  BufRead = "update",
  BufWinEnter = "update",
  TextChanged = "update",
  TextChangedI = "update",
  BufDelete = "remove",
  BufWipeout = "remove",
}

---@param _ async.Nursery
---@param push producers.Push
local bind = function(_, push)
  vim.api.nvim_create_autocmd(vim.tbl_keys(kinds), {
    group = lib.group,
    callback = function(args)
      push { kind = kinds[args.event], args = args }
    end,
  })

  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      push { kind = "update", args = { buf = buf } }
    end
  end
end

---@param buf integer
---@return string[]
local buffer_lines = function(buf)
  local count = vim.api.nvim_buf_line_count(buf)
  local row, height = (function()
    local win = vim.fn.bufwinid(buf)
    if win == -1 then
      return 0, count
    end

    local row = unpack(vim.api.nvim_win_get_cursor(win))
    return row - 1, vim.api.nvim_win_get_height(win)
  end)()

  local lo, hi = math.max(0, row - height), math.min(count, row + height + 1)
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
---@return string
local doc = function(opts, ctx, item)
  local parts = {}
  if not opts.same_filetype and item.filetype ~= "" then
    table.insert(parts, item.filetype .. opts.parent_scope)
  end
  if item.filename ~= "" then
    table.insert(parts, fs.fmt_path(ctx.cwd, item.filename, ctx.filename))
  end
  return table.concat(parts, "\n")
end

---@param settings config.Settings
M.idle = function(settings, events)
  local _ = settings
  local state = require("coq.producers.buffer").state
  local index = require "coq.producers.buffer.index"

  for buf, ev in pairs(events) do
    async.sleep(0)

    if ev.kind == "remove" then
      index.prune { buf = buf }
      state.last_tick[buf] = nil
    elseif ev.kind == "update" then
      local info = worker.main(function(...)
        return require("coq.producers.buffer").buffer_info(...)
      end, buf, state.last_tick[buf])

      if info then
        state.last_tick[info.buf] = info.tick
        index.prune { buf = info.buf }

        local kw = tokens.parse_iskeyword(info.iskeyword)
        local lines = info.lines and vim.iter(info.lines) --[[@as lib.Iterator<string>]]
          or atools.file_lines(info.filename)

        for word in tokens.words(kw, lines) do
          index.insert {
            buf = info.buf,
            word = word,
            filetype = info.filetype,
            filename = info.filename,
          }
        end
      end
    end
  end
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.buffers
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]
  local index = require "coq.producers.buffer.index"
  local util = require "coq.producers.util"
  local search_ctx = {
    keyword_before = ctx.keyword_before,
    filetype = opts.same_filetype and ctx.filetype or nil,
  }

  local items = util.dedup(index.search(search_ctx) --[[@as lib.Iterator<buffer.Item>]], function(it)
    return it.word
  end)

  for item in items do
    if item.word ~= ctx.cword then
      coroutine.yield {
        word = item.word,
        kind = "Text",
        menu = menu,
        info = doc(opts, ctx, item),
        meta = {
          filter = item.word,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
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
    key = function(ev)
      return ev.args.buf
    end,
    bind = bind,
    idle = function(...)
      require("coq.producers.buffer").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.buffer").matcher(...)
    end,
  }
end

return M
