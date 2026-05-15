local M = {}

M.pack = function(...)
  return { n = select("#", ...), ... }
end

M.unpack = function(packet)
  return unpack(packet, 1, packet.n)
end

M.closable = function(h, on_close)
  local state = { closed = false }
  local unwatch = function() end
  state.close = function()
    if state.closed then
      return
    end
    state.closed = true
    unwatch()
    on_close()
  end
  if h then
    unwatch = h.on_cancel(state.close)
  end
  return state
end

return M
