local async = require "coq.lib.async"
local broadcast = require "coq.lib.channels.broadcast"
local lib = require "coq.lib"

local events = broadcast.new()

vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
  group = lib.group,
  callback = function(args)
    events.push(args)
  end,
})

async.run(async.ROOT, function()
  for args in events.subscribe() do
  end
end)
