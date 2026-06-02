local runtime = require "coq.lib.async.runtime"

---@class channels.Packet
---@field n integer
---@field [integer] any

---@class channels.ClosableState: lib.Closable
---@field closed boolean

---@class channels.Cond
---@field wait fun()
---@field wake fun()

local M = {}

---@return channels.Cond
M.cond = function()
  local waiters = {}
  local cond = {}

  cond.wait = function()
    local f = runtime.future()
    table.insert(waiters, f)
    f.await()
  end

  cond.wake = function()
    local ws = waiters
    waiters = {}
    for _, f in pairs(ws) do
      f.resolve()
    end
  end

  ---@cast cond channels.Cond
  return cond
end

---@param ... any
---@return channels.Packet
M.pack = function(...)
  return { n = select("#", ...), ... }
end

---@param packet channels.Packet
---@return any ...
M.unpack = function(packet)
  return unpack(packet, 1, packet.n)
end

---@param on_close fun()
---@return channels.ClosableState
M.closable = function(on_close)
  local state = { closed = false }
  state.close = function()
    if state.closed then
      return
    end
    state.closed = true
    on_close()
  end
  return state
end

return M
