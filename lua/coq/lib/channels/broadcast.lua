local closable = require "coq.lib.closable"
local util = require "coq.lib.channels.util"

---@class channels.Broadcast<T>: lib.Closable
---@field replace fun(...: T): boolean
---@field subscribe fun(): fun(), fun(): T ...

local M = {}

---@generic T
---@return channels.Broadcast<T>
M.new = function()
  local current = nil
  local version = 0
  local changed = util.cond()

  local state = closable.new(changed.wake)

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
    local sub = closable.new(changed.wake)

    local iter = function()
      while true do
        if sub.closed then
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

    return sub.close, iter
  end

  return chan
end

return M
