-- Outstanding requests waiting on responses, keyed by id.
-- Two reservation modes:
--   rpc  — one-shot, cb receives (err, ...vals) decoded from a response frame
--   raw  — persistent, cb receives the raw frame; caller frees via release()

local make = function()
  local map = {}
  local id = 0
  return {
    reserve = function(cb)
      id = id + 1
      local my_id = id
      map[my_id] = { mode = "rpc", cb = cb }
      return my_id
    end,
    reserve_raw = function(cb)
      id = id + 1
      local my_id = id
      map[my_id] = { mode = "raw", cb = cb }
      return my_id, function()
        map[my_id] = nil
      end
    end,
    resolve = function(frame)
      local e = map[frame.id]
      if not e then
        return
      end
      if e.mode == "rpc" then
        map[frame.id] = nil
        if frame.ok then
          e.cb(nil, unpack(frame.values, 1, frame.n))
        else
          e.cb(frame.values[1] or "unknown error")
        end
      else
        e.cb(frame)
      end
    end,
    drain = function(reason)
      for _, e in pairs(map) do
        if e.mode == "rpc" then
          e.cb(reason)
        else
          e.cb { kind = "response", ok = false, n = 1, values = { reason } }
        end
      end
      map = {}
    end,
  }
end

return { make = make }
