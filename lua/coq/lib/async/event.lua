local runtime = require "coq.lib.async.runtime"
local sparse = require "coq.lib.sparse_table"

local M = {}

M.new = function()
  local is_set = false
  local waiters = sparse.new()

  local event = {}

  event.is_set = function()
    return is_set
  end

  event.set = function()
    if is_set then
      return
    end
    is_set = true

    local snapshot = waiters
    waiters = sparse.new()
    for _, f in snapshot.iter() do
      f.resolve()
    end
  end

  event.wait = function(h)
    if is_set then
      return true
    end

    local f = runtime.future()
    local key = waiters.push(f)
    f.await(h)
    if h and h.cancelled then
      waiters.remove(key)
      return false
    end
    return true
  end

  return event
end

return M
