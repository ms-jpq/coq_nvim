local lib = require "coq.lib"

local M = {}

---@type table<string, boolean>
local enabled = {}

---@param source string
---@param state boolean
M.set = function(source, state)
  enabled[source] = state
end

---@param source string
---@return boolean
M.is_enabled = function(source)
  return enabled[source] ~= false
end

---@generic C
---@param producer producers.Producer<C>
---@return producers.Producer<C>
M.wrap = function(producer)
  local source = producer.source
  return {
    source = source,
    idle = function(settings, ctx)
      if not M.is_enabled(source) then
        return
      end
      return producer.idle(settings, ctx)
    end,
    search = function(settings, ctx)
      if not M.is_enabled(source) then
        return lib.noop, lib.noop
      end
      return producer.search(settings, ctx)
    end,
  }
end

return M
