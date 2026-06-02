local async = require "coq.lib.async"

local M = {}

---@generic T
---@param timeout_ms? integer
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.new = function(timeout_ms, iter)
  if not timeout_ms or timeout_ms <= 0 then
    return iter
  end

  local deadline_ns = vim.uv.hrtime() + timeout_ms * 1e6
  local done = false

  return function()
    if done then
      return nil
    end
    local remaining_ms = math.max(0, math.floor((deadline_ns - vim.uv.hrtime()) / 1e6))
    local _, value = async.race {
      iter,
      function()
        async.sleep(remaining_ms)
      end,
    }

    if value == nil then
      done = true
    end
    return value
  end
end

return M
