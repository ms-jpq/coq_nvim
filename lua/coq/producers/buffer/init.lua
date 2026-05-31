local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"
local worker = require "coq.lib.worker"

---@class buffer.BufInfo
---@field buf integer
---@field lines string[]
---@field filetype string
---@field filename string
---@field iskeyword string

local M = {}

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
---@return buffer.BufInfo?
M.buffer_info = function(buf)
  atools.scheduled()

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end

  local count = vim.api.nvim_buf_line_count(buf)
  local row, height = (function()
    local win = vim.fn.bufwinid(buf)
    if win == -1 then
      return 0, count
    end
    return vim.api.nvim_win_get_cursor(win)[1] - 1, vim.api.nvim_win_get_height(win)
  end)()
  local lo = math.max(0, row - height)
  local hi = math.min(count, row + height + 1)

  return {
    buf = buf,
    lines = vim.api.nvim_buf_get_lines(buf, lo, hi, true),
    filetype = vim.bo[buf].filetype,
    filename = vim.api.nvim_buf_get_name(buf),
    iskeyword = vim.bo[buf].iskeyword,
  }
end

---@param opts config.BuffersClient
---@param item buffer.Item
---@param current_filetype string
---@return string
local doc = function(opts, item, current_filetype)
  local parts = {}
  if item.filetype ~= "" and item.filetype ~= current_filetype then
    table.insert(parts, item.filetype .. opts.parent_scope)
  end
  if item.filename ~= "" then
    table.insert(parts, item.filename)
  end
  return table.concat(parts, "\n")
end

---@param settings config.Settings
M.idle = function(settings, events)
  local _ = settings
  local index = require "coq.producers.buffer.index"

  for buf, ev in pairs(events) do
    if ev.kind == "remove" then
      index.prune { buf = buf }
    elseif ev.kind == "update" then
      local info = worker.main(function(b)
        return require("coq.producers.buffer").buffer_info(b)
      end, buf)
      if info then
        index.prune { buf = buf }
        local kw = tokens.parse_iskeyword(info.iskeyword)
        local lines = vim.iter(info.lines) --[[@as fun(): string?]]

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
  local search_ctx = {
    keyword_before = ctx.keyword_before,
    filetype = opts.same_filetype and ctx.filetype or nil,
  }

  for item in
    index.search(search_ctx) --[[@as fun(): buffer.Item?]]
  do
    if item.word ~= ctx.cword then
      coroutine.yield {
        word = item.word,
        kind = "Text",
        menu = menu,
        info = doc(opts, item, ctx.filetype),
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
---@return producers.Producer
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
