local lib = require "coq.lib"

local M = {}

---@type producers.SearchIter
M.dead_iter = setmetatable({ close = lib.noop }, {
  __call = function()
    return nil
  end,
})

return M
