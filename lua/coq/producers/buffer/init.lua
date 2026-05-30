local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"

local matcher = function(ctx)
  local index = require "coq.producers.buffer.index"
  for item in index.search(ctx) do
    coroutine.yield { word = item.word, meta = { filter = item.word } }
  end
end

local idle = function(events)
  local index = require "coq.producers.buffer.index"
  for _, ev in ipairs(events) do
    if ev.kind == "remove" then
      index.prune { buf = ev.buf }
    elseif ev.kind == "update" then
      index.prune { buf = ev.buf }
      for word, _ in pairs(ev.words) do
        index.insert { word = word, buf = ev.buf, filetype = ev.filetype }
      end
    end
  end
end

local update_kinds = {
  BufEnter = true,
  BufRead = true,
  BufWinEnter = true,
  TextChanged = true,
  TextChangedI = true,
}

local remove_kinds = {
  BufDelete = true,
  BufWipeout = true,
}

local M = threaded.new(idle, matcher)

local inner_bind = M.bind

M.bind = function(n)
  inner_bind(n, function(push)
    local on_event = function(args)
      local buf = args.buf
      if remove_kinds[args.event] then
        push { kind = "remove", buf = buf }
        return
      end

      if update_kinds[args.event] then
        if not vim.api.nvim_buf_is_loaded(buf) then
          return
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
        local words = tokens.locality(buf, lines)
        local filetype = vim.bo[buf].filetype
        push { kind = "update", buf = buf, words = words, filetype = filetype }
      end
    end

    vim.api.nvim_create_autocmd(vim.tbl_keys(update_kinds), {
      group = lib.group,
      callback = on_event,
    })

    vim.api.nvim_create_autocmd(vim.tbl_keys(remove_kinds), {
      group = lib.group,
      callback = on_event,
    })
  end)
end

return M
