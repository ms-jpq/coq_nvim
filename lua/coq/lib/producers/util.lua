local lib = require "coq.lib"
require "coq.lib.index.search"

local M = {}

---@type index.SearchIter
M.dead_iter = setmetatable({ close = lib.noop }, {
  __call = function()
    return nil
  end,
})

return M
