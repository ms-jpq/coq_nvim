if not os.getenv "COQ_V2" then
  return require "coq.legacy.coq"
end

local async = require "coq.lib.async"
local config = require "coq.config"
local insertion = require "coq.completions.insertion"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local nvim_options = require "coq.nvim_options"
local preview = require "coq.completions.preview"
local ranker_m = require "coq.lib.index.rank.ranker"
local supervisor = require "coq.lib.producers.supervisor"
local trigger = require "coq.completions.trigger"

local M = {}

do
  local unimplemented = function(name)
    ---@param cfg? table
    ---@return table?
    M.lsp_ensure_capabilities = function(cfg)
      return cfg
    end

    return function()
      vim.notify(("coq.%s is not yet implemented in v2"):format(name), vim.log.levels.WARN)
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
      local client = require "coq.producers.buffer"
      coroutine.yield(client)
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
  local ranker = ranker_m.new()

  async.entry(function()
    nursery.scope(function(n)
      sup.bind(n)
      trigger.bind(n, settings, ranker, sup)
      preview.bind(n, settings)
      insertion.bind(n, ranker)
    end)
  end)()

  return { settings = settings, supervisor = sup }
end

if (vim.g.coq_settings or {}).auto_start then
  M.setup()
end

return M
