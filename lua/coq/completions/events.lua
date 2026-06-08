local broadcast = require "coq.lib.channels.broadcast"
local buffers = require "coq.lib.buffers"
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

---@class completions.PumDoneEvent
---@field kind "done"
---@field completed_item vim.v.completed_item

---@class completions.PumClearEvent
---@field kind "clear"

---@alias completions.PumEvent completions.PumChangedEvent | completions.PumDoneEvent | completions.PumClearEvent

---@class completions.TriggerEvent
---@field manual boolean

---@class completions.IdleEvent
---@field synthetic boolean

---@alias completions.BufKind "update" | "remove"

---@class completions.BufEvent
---@field buf integer
---@field kind completions.BufKind

---@class completions.Events
---@field idle channels.Broadcast<completions.IdleEvent>
---@field bufs channels.Broadcast<completions.BufEvent>
---@field trigger channels.Broadcast<completions.TriggerEvent>
---@field completion channels.Broadcast<completions.PumEvent>
---@field leave channels.Broadcast<integer>

---@type table<string, completions.BufKind>
local BUF_KINDS = {
  BufEnter = "update",
  BufRead = "update",
  BufWinEnter = "update",
  BufFilePost = "update",
  TextChanged = "update",
  TextChangedI = "update",
  BufDelete = "remove",
  BufWipeout = "remove",
}

local COQ_LAST_SIZE = "__coq_last_size__"

---@param buf integer
---@return boolean
local is_completable = function(buf)
  local bo = vim.bo[buf]
  return bo.modifiable and bo.buftype ~= "prompt"
end

local M = {}

---@return completions.Events
M.new = function()
  ---@diagnostic disable-next-line: missing-fields
  local events = {} ---@type completions.Events

  do
    events.idle = broadcast.new()

    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = lib.group,
      callback = function()
        events.idle.replace { synthetic = false }
      end,
    })
  end

  do
    events.bufs = broadcast.new()

    vim.api.nvim_create_autocmd(vim.tbl_keys(BUF_KINDS), {
      group = lib.group,
      callback = function(args)
        events.bufs.replace { buf = args.buf, kind = BUF_KINDS[args.event] }
      end,
    })
  end

  do
    events.trigger = broadcast.new()

    vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
      group = lib.group,
      callback = function(args)
        if not is_completable(args.buf) then
          return
        end
        events.trigger.replace { manual = false }
      end,
    })

    vim.api.nvim_create_autocmd({ "InsertEnter", "BufEnter", "TextChanged" }, {
      group = lib.group,
      callback = function(args)
        if not is_completable(args.buf) then
          return
        end
        vim.b[args.buf][COQ_LAST_SIZE] = buffers.buf_size(args.buf)
      end,
    })

    vim.api.nvim_create_autocmd({ "TextChangedI" }, {
      group = lib.group,
      callback = function(args)
        if not is_completable(args.buf) then
          return
        end
        local prev = vim.b[args.buf][COQ_LAST_SIZE]
        local now = buffers.buf_size(args.buf)
        vim.b[args.buf][COQ_LAST_SIZE] = now
        if prev == nil or now >= prev then
          return
        end
        events.trigger.replace { manual = false }
      end,
    })
  end

  do
    events.completion = broadcast.new()

    vim.api.nvim_create_autocmd({ "CompleteChanged" }, {
      group = lib.group,
      callback = function()
        local ev = vim.tbl_extend("force", { kind = "changed" }, vim.v.event) --[[@as completions.PumChangedEvent]]
        events.completion.replace(ev)
      end,
    })
  end

  do
    vim.api.nvim_create_autocmd({ "CompleteDone" }, {
      group = lib.group,
      callback = function()
        local completed_item = vim.tbl_extend("force", {}, vim.v.completed_item)
        events.completion.replace { kind = "done", completed_item = completed_item }
      end,
    })
  end

  do
    events.leave = broadcast.new()

    vim.api.nvim_create_autocmd({ "InsertLeave" }, {
      group = lib.group,
      callback = function(args)
        events.completion.replace { kind = "clear" }
        events.leave.replace(args.buf)
      end,
    })
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
    local close, iter = chan.subscribe()
    defer(close)
    local prev = nil
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
