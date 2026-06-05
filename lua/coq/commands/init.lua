local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local help = require "coq.commands.help"
local lib = require "coq.lib"
local path_fmt = require "coq.producers.path_fmt"
local sources = require "coq.producers.snippets.sources"
local stats = require "coq.commands.stats"

local M = {}

local unimplemented = function(name)
  return function(...)
    vim.notify(string.format("coq.%s is not yet implemented in v2", name), vim.log.levels.WARN)
  end
end

M.Help = function(...)
  help.run { ... }
end

M.Now = unimplemented "Now"
M.deps = unimplemented "deps"

---@param settings config.Settings
---@param statsd index.Statsd
---@param events completions.Events
M.bind = function(settings, statsd, events)
  atools.scheduled()

  vim.api.nvim_create_user_command("COQhelp", function(opts)
    help.run(opts.fargs)
  end, {
    nargs = "*",
    complete = function(arglead)
      return vim
        .iter(help.complete())
        :filter(function(t)
          return vim.startswith(t, arglead)
        end)
        :totable()
    end,
  })

  vim.api.nvim_create_user_command("COQnow", function(opts)
    M.Now(unpack(opts.fargs))
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("COQdeps", function()
    M.deps()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command("COQstats", function()
    stats.show(statsd)
  end, { nargs = 0 })

  local snips = function()
    atools.scheduled()
    local cwd = vim.fn.getcwd()
    local current = vim.api.nvim_buf_get_name(0)
    ---@diagnostic disable-next-line: missing-fields
    local idle_ctx = { ---@type idle.Ctx
      cache_dir = vim.fs.joinpath(vim.fn.stdpath "cache", "coq"),
      rtps = vim.api.nvim_list_runtime_paths(),
    }

    local lines = lib.scope(function(defer)
      local close, iter = sources.list(settings, idle_ctx, nil)
      defer(close)
      return vim
        .iter(iter)
        :map(function(src)
          return "~> " .. path_fmt.fmt(cwd, src.path, current)
        end)
        :totable()
    end)

    atools.scheduled()
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    events.idle.replace { synthetic = true }
  end

  vim.api.nvim_create_user_command(
    "COQsnips",
    async.entry(function()
      snips()
    end),
    { nargs = 0 }
  )

  vim.api.nvim_create_user_command(
    "COQeval",
    async.entry(function()
      snips()
    end),
    { nargs = 0 }
  )
end

return M
