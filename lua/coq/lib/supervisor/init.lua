local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@param producers Producer[]
---@return Producer
M.new = function(producers)
  local search_handle = handle.new()
  search_handle.cancel()
  local idle_handle = handle.new()
  idle_handle.cancel()

  local current_close

  local sup = {}

  sup.search = function(ctx)
    if current_close then
      pcall(current_close)
    end
    idle_handle.cancel()
    search_handle = handle.new()

    local iters = {}
    for idx, p in ipairs(producers) do
      local row_iter
      iters[idx] = function()
        row_iter = row_iter or p.search(ctx)
        return row_iter()
      end
    end
    local merged = async.merge(iters, search_handle)
    current_close = merged.close

    local close = function()
      merged.close()
      search_handle.cancel()
    end
    local next = function()
      local _, row = merged()
      if row == nil then
        search_handle.cancel()
      end
      return row
    end
    return setmetatable({ close = close }, { __call = next })
  end

  sup.idle = function(ctx)
    if not search_handle.cancelled then
      return
    end
    idle_handle.cancel()
    idle_handle = handle.new()
    runtime.detach(idle_handle, function()
      async.scope(function(n)
        for _, p in ipairs(producers) do
          if p.idle then
            n.spawn(function()
              p.idle(ctx)
            end)
          end
        end
      end)
    end)
  end

  sup.close = function()
    search_handle.cancel()
    idle_handle.cancel()
    if current_close then
      pcall(current_close)
      current_close = nil
    end
    for _, p in ipairs(producers) do
      p.close()
    end
  end

  return sup
end

return M
