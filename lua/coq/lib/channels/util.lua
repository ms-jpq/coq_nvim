local M = {}

M.pack = function(...)
  return { n = select("#", ...), ... }
end

M.unpack = function(pkt)
  return unpack(pkt, 1, pkt.n)
end

M.bind_close = function(h, close_fn)
  if not h then
    return function() end
  end
  return h.on_cancel(close_fn)
end

return M
