if not os.getenv "COQ_V2" then
  return require "coq.legacy"
end

local async = require "coq.lib.async"
local config = require "coq.config"
local events_m = require "coq.completions.events"
local idle = require "coq.completions.idle"
local insertion = require "coq.completions.insertion"
local lib = require "coq.lib"
local nvim_options = require "coq.nvim_options"
local preview = require "coq.completions.preview"
local ranker_m = require "coq.lib.index.rank.ranker"
local supervisor = require "coq.lib.producers.supervisor"
local trigger = require "coq.completions.trigger"

local M = {}

---@param cfg? table
---@return table?
M.lsp_ensure_capabilities = function(cfg)
  return cfg
end

do
  local unimplemented = function(name)
    return function()
      vim.notify(string.format("coq.%s is not yet implemented in v2", name), vim.log.levels.WARN)
    end
  end

  M.Now = lib.noop
  M.deps = unimplemented "deps"
  M.Stats = unimplemented "Stats"
  M.Snips = unimplemented "Snips"
  M.Help = unimplemented "Help"

  local cmds = {
    COQnow = M.Now,
    COQdeps = M.deps,
    COQstats = M.Stats,
    COQsnips = M.Snips,
    COQhelp = M.Help,
  }

  for name, fn in pairs(cmds) do
    vim.api.nvim_create_user_command(name, fn, { nargs = "*" })
  end
end

---@param settings config.Settings
---@return fun(): producers.Producer?
local producers = function(settings)
  return coroutine.wrap(function()
    local clients = settings.clients

    if clients.buffers.enabled then
      coroutine.yield(require("coq.producers.buffer").new(settings))
    end

    if clients.tmux.enabled then
      coroutine.yield(require("coq.producers.tmux").new(settings))
    end
  end)
end

---@param opts? table
M.setup = function(opts)
  local merged = vim.tbl_deep_extend("force", vim.g.coq_settings or {}, opts or {})
  local settings = config.merged(merged)
  nvim_options.apply(settings)
  local p = vim.iter(async.wrap(producers(settings))):totable()
  local sup = supervisor.new(p)

  local ranker = ranker_m.new(settings.clients)
  local events = events_m.new()

  async.entry(function()
    async.scope(function(n)
      sup.bind(n)
      trigger.bind(n, settings, ranker, sup, events.trigger)
      preview.bind(n, settings, events.pum)
      insertion.bind(n, ranker, events.done)
      idle.bind(n, sup, events.idle)
    end)
  end)()
end

if (vim.g.coq_settings or {}).auto_start then
  M.setup()
end

return setmetatable(M, {
  __call = function()
    return M
  end,
})
