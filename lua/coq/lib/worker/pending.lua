-- Outstanding requests waiting on responses, keyed by id.

local make = function()
  local map = {}
  local id = 0
  return {
    reserve = function(cb)
      id = id + 1
      map[id] = cb
      return id
    end,
    resolve = function(frame)
      local cb = map[frame.id]
      map[frame.id] = nil
      if not cb then
        return
      end
      if frame.ok then
        cb(nil, unpack(frame.values, 1, frame.n))
      else
        cb(frame.values[1] or "unknown error")
      end
    end,
    drain = function(reason)
      for _, cb in pairs(map) do
        cb(reason)
      end
      map = {}
    end,
  }
end

return { make = make }
