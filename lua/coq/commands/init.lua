local atools = require "coq.lib.atools"
local help = require "coq.commands.help"
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
M.Snips = unimplemented "Snips"

---@param statsd index.Statsd
M.bind = function(statsd)
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

  vim.api.nvim_create_user_command("COQsnips", function(opts)
    M.Snips(unpack(opts.fargs))
  end, { nargs = "*" })
end

return M
