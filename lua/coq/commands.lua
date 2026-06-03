local lib = require "coq.lib"

local M = {}

local unimplemented = function(name)
  return function()
    vim.notify(string.format("coq.%s is not yet implemented in v2", name), vim.log.levels.WARN)
  end
end

M.Now = lib.noop
M.deps = lib.noop

M.Stats = unimplemented "Stats"
M.Snips = unimplemented "Snips"
M.Help = unimplemented "Help"

M.register = function()
  for name, fn in pairs {
    COQnow = M.Now,
    COQdeps = M.deps,
    COQstats = M.Stats,
    COQsnips = M.Snips,
    COQhelp = M.Help,
  } do
    vim.api.nvim_create_user_command(name, fn, { nargs = "*" })
  end
end

return M
