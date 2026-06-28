local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events_m = require "coq.completions.events"
local set = require "coq.lib.set"

---@class idle.Ctx
---@field ctx ctx.full
---@field config_dir string
---@field cache_dir string
---@field rtps string[]
---@field updated integer[]
---@field removed integer[]

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param sup producers.Producer<idle.Ctx>
---@param events completions.Events
M.bind = function(n, settings, sup, events)
  local rtps = vim.api.nvim_list_runtime_paths()
  local config_dir = vim.fn.stdpath "config"
  local cache_dir = vim.fs.joinpath(vim.fn.stdpath "cache", "coq")

  local carry = { updated = set.new {}, removed = set.new {} }
  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      carry.updated[buf] = true
    end
  end
  events.idle.replace { synthetic = true }

  events_m.subscribe_latest(n, events.bufs, function(ev)
    if ev.kind == "remove" then
      carry.updated[ev.buf] = nil
      carry.removed[ev.buf] = true
    else
      carry.removed[ev.buf] = nil
      carry.updated[ev.buf] = true
    end
  end)

  events_m.subscribe_latest(n, events.idle, function(ev)
    if not ev.synthetic then
      async.sleep(math.floor(settings.limits.idle_timeout * 1000))
    end

    local snapshot = carry
    carry = { updated = set.new {}, removed = set.new {} }

    atools.scheduled()
    sup.idle(settings, {
      ctx = context.full(),
      config_dir = config_dir,
      cache_dir = cache_dir,
      rtps = rtps,
      updated = vim.tbl_keys(snapshot.updated),
      removed = vim.tbl_keys(snapshot.removed),
    })
  end)
end

return M
