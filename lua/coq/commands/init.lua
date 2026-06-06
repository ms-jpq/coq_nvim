local atools = require "coq.lib.atools"
local help = require "coq.commands.help"
local lib = require "coq.lib"
local snippets = require "coq.commands.snippets"
local stats = require "coq.commands.stats"
local transition = require "coq.transition"

local M = {}

M.Help = function(...)
  help.run { ... }
end

M.deps = transition.deps

local snips_impl = lib.noop
local stats_impl = lib.noop

M.Snips = function(...)
  return snips_impl(...)
end

M.Stats = function(...)
  return stats_impl(...)
end

---@param settings config.Settings
---@param statsd index.Statsd
---@param events completions.Events
M.bind = function(settings, statsd, events)
  atools.scheduled()

  stats_impl = function()
    stats.show(statsd)
  end
  snips_impl = snippets.bind(settings, events)

  vim.api.nvim_create_user_command("COQnow", lib.noop, { nargs = "*" })
  vim.api.nvim_create_user_command("COQdeps", M.deps, { nargs = 0 })

  vim.api.nvim_create_user_command("COQstats", function()
    M.Stats()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("COQhelp", function(opts)
    help.run(opts.fargs)
  end, {
    nargs = "*",
    complete = function(arglead)
      return vim
        .iter(vim.tbl_keys(help.TOPICS))
        :filter(function(t)
          return vim.startswith(t, arglead)
        end)
        :totable()
    end,
  })

  vim.api.nvim_create_user_command("COQsnips", function(opts)
    M.Snips(opts.fargs)
  end, {
    nargs = "*",
    complete = function(arglead)
      return vim
        .iter(snippets.SUBCMDS)
        :filter(function(t)
          return vim.startswith(t, arglead)
        end)
        :totable()
    end,
  })
end

return M
