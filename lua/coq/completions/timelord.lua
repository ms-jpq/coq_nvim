local async = require "coq.lib.async"
local default_dict = require "coq.lib.default_dict"
local ring_m = require "coq.lib.ring"

---@class completions.TimeLord
---@field guard fun(key: string, recommended_ms: integer, fn: fun(): any): any
---@field guard_stream_1 fun(key: string, recommended_ms: integer, iter: lib.Iterator<any>): lib.Iterator<any>

local MIN_SAMPLES, MAX_SAMPLES = 4, 32
local FACTOR = 1.5

---@param samples number[]
---@return number ms
local p95 = function(samples)
  if #samples < MIN_SAMPLES then
    return 0
  end
  table.sort(samples)
  return samples[math.ceil(#samples * 0.95)]
end

local M = {}

---@return completions.TimeLord
M.new = function()
  ---@type lib.DefaultDict<string, lib.Ring<number>>
  local rings = default_dict.new(function()
    return ring_m.new(MAX_SAMPLES)
  end)

  ---@diagnostic disable-next-line: missing-fields
  local lord = {} ---@type completions.TimeLord

  lord.guard = function(key, recommended_ms, fn)
    return lord.guard_stream_1(key, recommended_ms, fn)()
  end

  lord.guard_stream_1 = function(key, recommended_ms, iter)
    if recommended_ms <= 0 then
      return iter
    end

    local effective_ms = math.max(recommended_ms, math.floor(p95(rings[key].items()) * FACTOR))

    ---@type integer?
    local t0 = vim.uv.hrtime()
    local deadline_ns = t0 + effective_ms * 1e6
    return function()
      local remaining = math.max(0, math.floor((deadline_ns - vim.uv.hrtime()) / 1e6))
      local value = async.wait(remaining, iter)

      if value ~= nil and t0 then
        rings[key].push((vim.uv.hrtime() - t0) / 1e6)
        t0 = nil
      end
      return value
    end
  end

  return lord
end

---@generic C: { manual: boolean, filetype: string }
---@param lord completions.TimeLord
---@param producer producers.Producer<C>
---@return producers.Producer<C>
M.wrap = function(lord, producer)
  return {
    source = producer.source,
    close = producer.close,
    idle = producer.idle,
    search = function(settings, ctx)
      local timeout_ms = ctx.manual and vim.o.completetimeout or vim.o.autocompletetimeout
      local key = producer.source .. ":" .. ctx.filetype

      local close, iter = producer.search(settings, ctx)
      local timed = lord.guard_stream_1(key, timeout_ms, iter)
      return close, timed
    end,
  }
end

return M
