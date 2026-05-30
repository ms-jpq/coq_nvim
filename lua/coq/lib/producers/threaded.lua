local lib = require "coq.lib"
local producer = require "coq.lib.producers"
local worker = require "coq.lib.worker"

local M = {}

---@type producers.NewProducer
M.new = function(spec)
  local w = worker.spawn()
  return producer.new {
    key = spec.key,
    bind = spec.bind,
    idle = function(events, ctx)
      w.queue(spec.idle, events, ctx)
    end,
    matcher = function(ctx)
      lib.scope(function(defer)
        local stream = w.queue_stream(spec.matcher, ctx)
        defer(stream.close)

        for item in stream do
          coroutine.yield(item)
        end
      end)
    end,
  }
end

return M
