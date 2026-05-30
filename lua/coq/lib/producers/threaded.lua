local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local queue = require "coq.lib.queue"
local worker = require "coq.lib.worker"

local M = {}

---@type producers.NewProducer
M.new = function(idle, matcher)
  local w = worker.spawn()
  local event_bus = queue.new()
  local ph = handle.new()

  local _ = ph.on_cancel(w.close)

  local db = { close = ph.cancel, queue = w.queue }

  db.notify = function(event)
    if ph.cancelled then
      return
    end
    event_bus.push(event)
  end

  db.idle = function(ctx)
    if ph.cancelled then
      return
    end
    local batch = {}
    for event in event_bus.pop do
      table.insert(batch, event)
    end
    if #batch > 0 then
      w.queue(idle, batch, ctx)
    end
  end

  db.search = function(ctx)
    if ph.cancelled then
      return lib.dead_iter
    end
    return w.queue_stream(matcher, ctx)
  end

  ---@cast db producers.Producer
  return db
end

return M
