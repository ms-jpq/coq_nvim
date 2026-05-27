local worker = require "coq.lib.worker"

local M = {}

---@return Producer
M.new = function(matcher, idle)
  local w = worker.spawn()

  local db = { close = w.close, queue = w.queue }

  db.idle = function(ctx)
    if idle then
      return w.queue(idle, ctx)
    end
  end

  db.search = function(ctx)
    local stream = w.queue_stream(matcher, ctx)

    local closed = false
    local close = function()
      if not closed then
        closed = true
        stream.close()
      end
    end

    local it = { close = close }

    local next = function()
      local row = stream()
      if row == nil then
        close()
      end
      return row
    end

    return setmetatable(it, { __call = next })
  end

  return db
end

return M
