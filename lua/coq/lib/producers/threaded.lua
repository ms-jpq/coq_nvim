local lib = require "coq.lib"
local producer = require "coq.lib.producers"
local worker = require "coq.lib.worker"

local M = {}

---@type producers.NewProducer
M.new = function(spec)
  local w = worker.spawn()
  return producer.new {
    settings = spec.settings,
    key = spec.key,
    bind = spec.bind,
    idle = function(settings, events, ctx)
      w.queue(spec.idle, settings, events, ctx)
    end,
    matcher = function(settings, ctx)
      lib.scope(function(defer)
        local stream = w.queue_stream(spec.matcher, settings, ctx)
        defer(stream.close)

        for item in stream do
          coroutine.yield(item)
        end
      end)
    end,
  }
end

return M
