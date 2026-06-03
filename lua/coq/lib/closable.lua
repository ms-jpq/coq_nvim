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

---@generic T
---@param producer fun(defer: fun(cleanup: fun()))
---@return fun() close
---@return lib.Iterator<T> iter
M.iter = function(producer)
  local async = require "coq.lib.async"

  local defers = {}

  local state = M.new(function()
    local snapshot = defers
    defers = {}
    lib.scope(function(defer)
      for _, d in ipairs(snapshot) do
        defer(d)
      end
    end)
  end)

  local inner = async.wrap(function()
    if state.closed then
      return
    end
    lib.scope(function(defer)
      defer(state.close)
      producer(function(d)
        table.insert(defers, d)
      end)
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
