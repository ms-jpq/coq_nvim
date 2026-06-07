local atools = require "coq.lib.atools"
local help = require "coq.commands.help"
local lib = require "coq.lib"
local snippets = require "coq.commands.snippets"
local source = require "coq.commands.source"
local stats = require "coq.commands.stats"
local transition = require "coq.transition"

local snips_impl = lib.noop
local stats_impl = lib.noop

local M = {
  deps = transition.deps,
  Help = function(...)
    help.run { ... }
  end,
  Snips = function(...)
    return snips_impl(...)
  end,
  Stats = function(...)
    return stats_impl(...)
  end,
}

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
        stats_impl()
      end,
    },
    help = {
      run = help.run,
      complete = function(arglead)
        return startswith_filter(arglead, vim.tbl_keys(help.TOPICS))
      end,
    },
    snips = {
      run = function(fargs)
        snips_impl(fargs)
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
  local sub = subcommands[fargs[1] or ""]
  if sub then
    sub.run(vim.list_slice(fargs, 2))
  else
    vim.notify(
      fargs[1] and "COQ: unknown subcommand '" .. fargs[1] .. "'" or "COQ: missing subcommand — try :COQ help",
      vim.log.levels.ERROR
    )
  end
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
  return sub and sub.complete and sub.complete(arglead, cmdline) or {}
end

local DEPRECATED = { COQstats = "stats", COQhelp = "help", COQsnips = "snips" }

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

  for old, new in pairs(DEPRECATED) do
    local sub = subcommands[new]
    vim.api.nvim_create_user_command(old, function(opts)
      vim.notify(":" .. old .. " is deprecated; use :COQ " .. new, vim.log.levels.WARN)
      sub.run(opts.fargs)
    end, {
      nargs = "*",
      complete = sub.complete and function(arglead)
        return sub.complete(arglead, "")
      end or nil,
    })
  end
end

return M
