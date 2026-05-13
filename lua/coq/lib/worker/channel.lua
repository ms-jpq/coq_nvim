local async = require "coq.lib.async"

local M = {}

local queue = function()
  local push, pop = {}, {}
  local q = {}

  q.push = function(val)
    table.insert(push, val)
  end

  q.pop = function()
    if #pop == 0 then
      while #push ~= 0 do
        table.insert(pop, table.remove(push))
      end
    end
    return table.remove(pop)
  end

  return setmetatable(q, {
    __len = function()
      return #push + #pop
    end,
  })
end

M.mpsc = function()
  local q = queue()
  local waiter = nil
  return {
    push = function(item)
      if waiter then
        local r = waiter
        waiter = nil
        r(item)
      else
        q.push(item)
      end
    end,
    pull = function()
      if #q > 0 then
        return q.pop()
      end
      local resolve, await = async.future()
      waiter = resolve
      return await()
    end,
  }
end

return M
