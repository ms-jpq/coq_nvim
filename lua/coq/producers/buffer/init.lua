local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"

local matcher = function(ctx)
  local state = require "coq.producers.buffer.state"
  for _, words in pairs(state.bufs) do
    for word in pairs(words) do
      if word ~= ctx.cword then
        coroutine.yield { word = word, meta = { filter = word } }
      end
    end
  end
end

local idle = function(events)
  local state = require "coq.producers.buffer.state"
  for _, ev in ipairs(events) do
    if ev.kind == "remove" then
      state.bufs[ev.buf] = nil
    else
      state.bufs[ev.buf] = ev.words
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
        push { kind = "update", buf = buf, words = words }
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
