local runtime = require "coq.lib.async._runtime"

---@class channels.Packet
---@field n integer
---@field [integer] any

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

return M
