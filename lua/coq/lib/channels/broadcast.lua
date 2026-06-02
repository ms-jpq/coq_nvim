local util = require "coq.lib.channels.util"

---@class channels.BroadcastSub<T>: lib.Closable
---@overload fun(): T ...

---@class channels.Broadcast<T>: lib.Closable
---@field replace fun(...: T): boolean
---@field subscribe fun(): channels.BroadcastSub<T>

local M = {}

---@generic T
---@return channels.Broadcast<T>
M.new = function()
  local current = nil
  local version = 0
  local changed = util.cond()

  local state = util.closable(changed.wake)

  local chan = { close = state.close }

  chan.replace = function(...)
    if state.closed then
      return false
    end
    current = util.pack(...)
    version = version + 1
    changed.wake()
    return true
  end

  chan.subscribe = function()
    local seen = 0
    local closed = false

    local it = {}
    it.close = function()
      closed = true
      changed.wake()
    end

    local next = function()
      while true do
        if closed then
          return nil
        end
        if version ~= seen then
          seen = version
          ---@cast current -nil
          return util.unpack(current)
        end
        if state.closed then
          return nil
        end
        changed.wait()
      end
    end

    return setmetatable(it, { __call = next })
  end

  return chan
end

return M
