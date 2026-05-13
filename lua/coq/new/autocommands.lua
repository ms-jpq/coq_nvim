local async = require "coq.lib.async"
local broadcast = require "coq.lib.channels.broadcast"
local lib = require "coq.lib"

local events = broadcast.new()

vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
  group = lib.group,
  callback = events.replace,
})

async.thunk(function()
  lib.scope(function(defer)
    local iter = events.subscribe()
    defer(iter.close)

    for args in iter do
    end
  end)
end)()
