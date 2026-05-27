local worker = require "coq.lib.worker"

local M = {}

---@type NewProducer
M.new = function(idle, matcher)
  local w = worker.spawn()

  local db = { close = w.close, queue = w.queue }

  db.idle = function(ctx)
    return w.queue(idle, ctx)
  end

  db.search = function(ctx)
    return w.queue_stream(matcher, ctx)
  end

  return db
end

return M
