if not os.getenv "COQ_V2" then
  return require "coq.legacy"
end

local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local config = require "coq.config"
local events_m = require "coq.completions.events"
local idle = require "coq.completions.idle"
local insertion = require "coq.completions.insertion"
local lib = require "coq.lib"
local nvim_options = require "coq.nvim_options"
local p_buffers = require "coq.producers.buffers"
local p_ctags = require "coq.producers.ctags"
local p_lsp = require "coq.producers.lsp"
local p_paths = require "coq.producers.paths"
local p_registers = require "coq.producers.registers"
local p_snippets = require "coq.producers.snippets"
local p_tmux = require "coq.producers.tmux"
local p_treesitter = require "coq.producers.treesitter"
local preview = require "coq.completions.preview"
local ranker_m = require "coq.lib.index.rank.ranker"
local resolver_m = require "coq.completions.resolver"
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

---@param clients config.Clients
---@return fun(): producers.Producer<ctx.full>?
local producers = function(clients)
  return async.wrap(function()
    if clients.buffers.enabled then
      coroutine.yield(p_buffers.new())
    end

    if clients.registers.enabled then
      coroutine.yield(p_registers.new())
    end

    if clients.tmux.enabled then
      coroutine.yield(p_tmux.new())
    end

    if clients.paths.enabled then
      coroutine.yield(p_paths.new())
    end

    if clients.tree_sitter.enabled then
      coroutine.yield(p_treesitter.new())
    end

    if clients.lsp.enabled then
      coroutine.yield(p_lsp.new())
    end

    if clients.tags.enabled then
      coroutine.yield(p_ctags.new())
    end

    if clients.snippets.enabled then
      coroutine.yield(p_snippets.new())
    end
  end)
end

local started = false

---@param opts? table
M.setup = function(opts)
  if started then
    return
  end
  started = true

  async.entry(function()
    async.scope(function(n)
      local merged = vim.tbl_deep_extend("force", vim.g.coq_settings or {}, opts or {})
      local settings = config.merged(merged)

      atools.scheduled()
      nvim_options.apply(settings)

      local p = vim.iter(producers(settings.clients)):totable()
      local sup = supervisor.new(p)

      local ranker = ranker_m.new(settings.clients)
      local events = events_m.new()
      local resolver = resolver_m.new(n)

      sup.bind(n)
      trigger.bind(n, settings, ranker, resolver, sup, events.trigger)
      preview.bind(n, settings, resolver, events.pum)
      insertion.bind(n, settings, resolver, ranker, events.done)
      idle.bind(n, settings, sup, events)
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
