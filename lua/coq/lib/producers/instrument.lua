local closable = require "coq.lib.closable"

local M = {}

---@generic C
---@param statsd index.Statsd
---@param producer producers.Producer<C>
---@return producers.Producer<C>
M.wrap = function(statsd, producer)
  return {
    source = producer.source,
    close = producer.close,
    idle = producer.idle,
    search = function(settings, ctx)
      local rec = statsd.record(producer.source)
      local exhausted = false

      return closable.iter(function(defer)
        defer(function()
          rec.done(not exhausted)
        end)
        local close, iter = producer.search(settings, ctx)
        defer(close)

        for batch in iter do
          rec.tally(#batch)
          coroutine.yield(batch)
        end
        exhausted = true
      end)
    end,
  }
end

return M
