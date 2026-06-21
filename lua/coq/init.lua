if vim.g.coq_v1 or vim.fn.has "nvim-0.12" == 0 then
  return require "coq.legacy"
end

local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local commands = require "coq.commands"
local config = require "coq.config"
local events_m = require "coq.completions.events"
local ghost = require "coq.completions.ghost"
local idle = require "coq.completions.idle"
local insertion = require "coq.completions.insertion"
local instrument = require "coq.lib.producers.instrument"
local lib = require "coq.lib"
local nvim_options = require "coq.nvim_options"
local p_buffers = require "coq.producers.buffers"
local p_lsp = require "coq.producers.lsp"
local p_paths = require "coq.producers.paths"
local p_registers = require "coq.producers.registers"
local p_snippets = require "coq.producers.snippets"
local p_tags = require "coq.producers.tags"
local p_third_party = require "coq.producers.third_party"
local p_tmux = require "coq.producers.tmux"
local p_tree_sitter = require "coq.producers.tree_sitter"
local preview = require "coq.completions.preview"
local resolver_m = require "coq.completions.resolver"
local statsd_m = require "coq.lib.index.rank.statsd"
local supervisor = require "coq.lib.producers.supervisor"
local timelord_m = require "coq.completions.timelord"
local toggle = require "coq.lib.producers.toggle"
local transition = require "coq.transition"
local trigger = require "coq.completions.trigger"

local M = {
  deps = commands.deps,
  Help = commands.Help,
  Now = lib.noop,
  Snips = commands.Snips,
  Stats = commands.Stats,
}

---@generic T
---@param cfg? T
---@return T?
M.lsp_ensure_capabilities = function(cfg)
  transition.lsp_ensure_capabilities()
  return cfg
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
      coroutine.yield(p_tree_sitter.new())
    end

    if clients.lsp.enabled then
      coroutine.yield(p_lsp.new())
    end

    if clients.tags.enabled then
      coroutine.yield(p_tags.new())
    end

    if clients.snippets.enabled then
      coroutine.yield(p_snippets.new())
    end

    if clients.third_party.enabled then
      coroutine.yield(p_third_party.new())
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
      atools.scheduled()

      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = lib.group,
        once = true,
        callback = n.cancel,
      })

      local merged = vim.tbl_deep_extend("force", vim.g.coq_settings or {}, opts or {})
      local settings = config.merged(merged)
      transition.audit(merged)

      local statsd = statsd_m.new(settings)
      local lord = timelord_m.new()

      local ps = vim
        .iter(producers(settings.clients))
        :map(function(prod)
          return timelord_m.wrap(lord, toggle.wrap(instrument.wrap(statsd, prod)))
        end)
        :totable()
      local sup = supervisor.new(ps)

      local events = events_m.new()
      local resolver = resolver_m.new(n, lord)

      nvim_options.apply(settings, events)

      idle.bind(n, settings, sup, events)
      trigger.bind(n, settings, statsd, resolver, sup, events)
      preview.bind(n, settings, resolver, events.completion)
      ghost.bind(n, settings, events)
      insertion.bind(n, settings, resolver, statsd, events.completion)
      commands.bind(settings, statsd, events)
    end)
  end)()
end

if vim.g.coq_settings then
  M.setup {}
end

return setmetatable(M, {
  __call = function()
    return M
  end,
})
