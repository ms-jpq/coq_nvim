local broadcast = require "coq.lib.channels.broadcast"
local context = require "coq.lib.context"
local insertion = require "coq.completions.insertion"
local lib = require "coq.lib"

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param ranker index.Ranker
---@param sup producers.Producer
M.bind = function(n, settings, ranker, sup)
  local events = broadcast.new()

  vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
    group = lib.group,
    callback = events.replace,
  })

  n.spawn(function(defer)
    local iter = events.subscribe()
    defer(iter.close)

    for _ in iter do
      n.spawn(function()
        local ctx = context.full()
        insertion.complete(ctx, settings, ranker, sup.search(ctx))
      end)
    end
  end)
end

return M
