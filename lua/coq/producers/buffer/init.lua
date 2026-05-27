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

local M = threaded.new(idle, matcher)

local enqueue = M.notify

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

M.notify = function(args)
  local buf = args.buf
  if remove_kinds[args.event] then
    enqueue { kind = "remove", buf = buf }
    return
  end

  if update_kinds[args.event] then
    if not vim.api.nvim_buf_is_loaded(buf) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    local words = tokens.locality(buf, lines)
    enqueue { kind = "update", buf = buf, words = words }
  end
end

if not vim.is_thread() then
  vim.api.nvim_create_autocmd(vim.tbl_keys(update_kinds), {
    group = lib.group,
    callback = M.notify,
  })

  vim.api.nvim_create_autocmd(vim.tbl_keys(remove_kinds), {
    group = lib.group,
    callback = M.notify,
  })
end

return M
