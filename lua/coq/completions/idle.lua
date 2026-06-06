local async = require "coq.lib.async"
local context = require "coq.lib.context"
local events_m = require "coq.completions.events"
local set = require "coq.lib.set"

---@class idle.Ctx
---@field ctx ctx.full
---@field config_dir string
---@field cache_dir string
---@field rtps string[]
---@field updated table<integer, true>
---@field removed table<integer, true>

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param sup producers.Producer<idle.Ctx>
---@param events completions.Events
M.bind = function(n, settings, sup, events)
  events.idle.replace { synthetic = true }

  local carry = { updated = set.new {}, removed = set.new {} }
  local rtps = vim.api.nvim_list_runtime_paths()
  local config_dir = vim.fn.stdpath "config"
  local cache_dir = vim.fs.joinpath(vim.fn.stdpath "cache", "coq")

  events_m.subscribe_latest(n, events.idle, function(ev)
    if not ev.synthetic then
      async.sleep(math.floor(settings.limits.idle_timeout * 1000))
    end

    local diff = events.drain_bufs()
    for buf in pairs(diff.removed) do
      carry.updated[buf] = nil
      carry.removed[buf] = true
    end
    for buf in pairs(diff.updated) do
      carry.removed[buf] = nil
      carry.updated[buf] = true
    end

    sup.idle(settings, {
      ctx = context.full(),
      config_dir = config_dir,
      cache_dir = cache_dir,
      rtps = rtps,
      updated = carry.updated,
      removed = carry.removed,
    })

    carry = { updated = set.new {}, removed = set.new {} }
  end)
end

return M
