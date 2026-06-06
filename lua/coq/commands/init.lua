local atools = require "coq.lib.atools"
local help = require "coq.commands.help"
local lib = require "coq.lib"
local snippets = require "coq.commands.snippets"
local source = require "coq.commands.source"
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

---@param arglead string
---@param items string[]
---@return string[]
local startswith_filter = function(arglead, items)
  return vim
    .iter(items)
    :filter(function(t)
      return vim.startswith(t, arglead)
    end)
    :totable()
end

---@class commands.Subcommand
---@field run fun(fargs: string[])
---@field complete? fun(arglead: string, cmdline: string): string[]

---@param settings config.Settings
---@return table<string, commands.Subcommand>
local subcommands_of = function(settings)
  return {
    stats = {
      run = function()
        M.Stats()
      end,
    },
    help = {
      run = function(fargs)
        help.run(fargs)
      end,
      complete = function(arglead)
        return startswith_filter(arglead, vim.tbl_keys(help.TOPICS))
      end,
    },
    snips = {
      run = function(fargs)
        M.Snips(fargs)
      end,
      complete = function(arglead)
        return startswith_filter(arglead, snippets.SUBCMDS)
      end,
    },
    source = {
      run = function(fargs)
        source.run(settings, fargs)
      end,
      complete = function(arglead, cmdline)
        return source.complete(settings, arglead, cmdline)
      end,
    },
  }
end

---@param subcommands table<string, commands.Subcommand>
---@param fargs string[]
local dispatch = function(subcommands, fargs)
  local name = fargs[1]
  if not name then
    vim.notify("COQ: missing subcommand — try :COQ help", vim.log.levels.ERROR)
    return
  end
  local sub = subcommands[name]
  if not sub then
    vim.notify("COQ: unknown subcommand '" .. name .. "'", vim.log.levels.ERROR)
    return
  end
  sub.run(vim.list_slice(fargs, 2))
end

---@param subcommands table<string, commands.Subcommand>
---@param arglead string
---@param cmdline string
---@return string[]
local complete_root = function(subcommands, arglead, cmdline)
  local parts = vim.split(cmdline, "%s+", { trimempty = false })
  if #parts <= 2 then
    return startswith_filter(arglead, vim.tbl_keys(subcommands))
  end
  local sub = subcommands[parts[2]]
  if sub and sub.complete then
    return sub.complete(arglead, cmdline)
  end
  return {}
end

---@param old_name string
---@param new_form string
---@param impl fun(opts: any)
---@param complete? fun(arglead: string, cmdline: string): string[]
local register_deprecated = function(old_name, new_form, impl, complete)
  vim.api.nvim_create_user_command(old_name, function(opts)
    vim.notify(":" .. old_name .. " is deprecated; use :COQ " .. new_form, vim.log.levels.WARN)
    impl(opts)
  end, {
    nargs = "*",
    complete = complete,
  })
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

  local subcommands = subcommands_of(settings)

  vim.api.nvim_create_user_command("COQ", function(opts)
    dispatch(subcommands, opts.fargs)
  end, {
    nargs = "*",
    complete = function(arglead, cmdline)
      return complete_root(subcommands, arglead, cmdline)
    end,
  })

  vim.api.nvim_create_user_command("COQnow", lib.noop, { nargs = "*" })
  vim.api.nvim_create_user_command("COQdeps", M.deps, { nargs = 0 })

  register_deprecated("COQstats", "stats", function()
    M.Stats()
  end)
  register_deprecated("COQhelp", "help", function(opts)
    help.run(opts.fargs)
  end, function(arglead)
    return startswith_filter(arglead, vim.tbl_keys(help.TOPICS))
  end)
  register_deprecated("COQsnips", "snips", function(opts)
    M.Snips(opts.fargs)
  end, function(arglead)
    return startswith_filter(arglead, snippets.SUBCMDS)
  end)
end

return M
