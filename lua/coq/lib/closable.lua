local lib = require "coq.lib"

---@class lib.Closable
---@field close fun()

---@class lib.ClosableState : lib.Closable
---@field closed boolean

local M = {}

---@param on_close fun()
---@return lib.ClosableState
M.new = function(on_close)
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

---@class lib.ClosableSequence: lib.ClosableState
---@field add fun(cleanup: fun())

---@param ord 1 | -1
---@return lib.ClosableSequence
M.seq = function(ord)
  assert(ord == -1 or ord == 1)

  local defers = {}
  local state = M.new(function()
    local snapshot = defers
    defers = {}
    lib.scope(function(defer)
      local first, last, step = 1, #snapshot, 1
      if ord == 1 then
        first, last, step = #snapshot, 1, -1
      end
      for i = first, last, step do
        defer(snapshot[i])
      end
    end)
  end)

  ---@cast state lib.ClosableSequence
  state.add = function(cleanup)
    assert(not state.closed, "cleanup sequence is closed")
    table.insert(defers, cleanup)
  end
  return state
end

---@generic T
---@param producer fun(defer: fun(cleanup: fun()))
---@return fun() close
---@return lib.Iterator<T> iter
M.iter = function(producer)
  local async = require "coq.lib.async"
  local state = M.seq(-1)

  local inner = async.wrap(function()
    if state.closed then
      return
    end
    lib.scope(function(defer)
      defer(state.close)
      producer(state.add)
    end)
  end)

  local iter = function()
    if state.closed then
      return nil
    end
    return inner()
  end

  return state.close, iter
end

return M
