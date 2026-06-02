local broadcast = require "coq.lib.channels.broadcast"
local errs = require "coq.lib.errs"
local lib = require "coq.lib"

---@class completions.PumChangedEvent : vim.v.event
---@field kind "changed"
---@field completed_item vim.v.completed_item
---@field row integer
---@field col integer
---@field height integer
---@field width integer
---@field scrollbar boolean

---@class completions.PumClearEvent
---@field kind "clear"

---@alias completions.PumEvent completions.PumChangedEvent | completions.PumClearEvent

---@class completions.BufDiff
---@field updated table<integer, true>
---@field removed table<integer, true>

---@class completions.Events
---@field trigger channels.Broadcast<nil>
---@field pum channels.Broadcast<completions.PumEvent>
---@field done channels.Broadcast<vim.v.completed_item>
---@field idle channels.Broadcast<nil>
---@field drain_bufs fun(): completions.BufDiff

local BUF_KINDS = {
  BufEnter = "update",
  BufRead = "update",
  BufWinEnter = "update",
  TextChanged = "update",
  TextChangedI = "update",
  BufDelete = "remove",
  BufWipeout = "remove",
}

local M = {}

---@return completions.Events
M.new = function()
  local bufs = { updated = {}, removed = {} }

  ---@type completions.Events
  local events = {
    trigger = broadcast.new(),
    pum = broadcast.new(),
    done = broadcast.new(),
    idle = broadcast.new(),
    drain_bufs = function()
      local p = bufs
      bufs = { updated = {}, removed = {} }
      return p
    end,
  }

  vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
    group = lib.group,
    callback = function(args)
      events.trigger.replace(args)
    end,
  })

  vim.api.nvim_create_autocmd({ "CompleteChanged" }, {
    group = lib.group,
    callback = function()
      local ev = vim.tbl_extend("force", { kind = "changed" }, vim.v.event) --[[@as completions.PumChangedEvent]]
      events.pum.replace(ev)
    end,
  })

  vim.api.nvim_create_autocmd({ "CompleteDone" }, {
    group = lib.group,
    callback = function()
      events.pum.replace { kind = "clear" }
      events.done.replace(vim.v.completed_item)
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave" }, {
    group = lib.group,
    callback = function()
      events.pum.replace { kind = "clear" }
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = lib.group,
    callback = function(args)
      events.idle.replace(args)
    end,
  })

  vim.api.nvim_create_autocmd(vim.tbl_keys(BUF_KINDS), {
    group = lib.group,
    callback = function(args)
      local kind = BUF_KINDS[args.event]
      if kind == "remove" then
        bufs.updated[args.buf] = nil
        bufs.removed[args.buf] = true
      else
        bufs.removed[args.buf] = nil
        bufs.updated[args.buf] = true
      end
    end,
  })

  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      bufs.updated[buf] = true
    end
  end

  return events
end

---@generic T
---@param n async.Nursery
---@param chan channels.Broadcast<T>
---@param handler fun(ev: T)
M.subscribe_latest = function(n, chan, handler)
  local safe = errs.with_reporting(handler)

  n.spawn(function(defer)
    local iter = chan.subscribe()
    defer(iter.close)
    local prev
    for ev in iter do
      if prev then
        prev.cancel()
      end
      prev = n.spawn(function()
        safe(ev)
      end)
    end
  end)
end

return M
