local queue = require "coq.lib.queue"
local worker = require "coq.lib.worker"

local M = {}

---@type producers.NewProducer
M.new = function(idle, matcher)
  local w = worker.spawn()
  local event_bus = queue.new()
  local closed = false

  local db = { queue = w.queue }

  db.close = function()
    closed = true
    w.close()
  end

  db.notify = function(event)
    if closed then
      return
    end
    event_bus.push(event)
  end

  db.idle = function(ctx)
    local batch = {}
    for event in event_bus.pop do
      table.insert(batch, event)
    end
    if #batch > 0 then
      w.queue(idle, batch, ctx)
    end
  end

  db.search = function(ctx)
    return w.queue_stream(matcher, ctx)
  end

  ---@cast db producers.Producer
  return db
end

return M
