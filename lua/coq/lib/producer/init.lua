local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

---@class Producer
---@field search fun(ctx: any): table
---@field idle? fun(ctx: any)
---@field close fun()
---@field queue? function

local M = {}

---@return Producer
M.new = function(matcher, idle)
  local db = {}

  db.close = lib.noop

  db.queue = function(fn, ...)
    return fn(...)
  end

  if idle then
    db.idle = idle
  end

  db.search = function(ctx)
    local h = handle.new(runtime.current())

    local stream = runtime.wrap(function()
      matcher(ctx)
    end, h)

    local it = { close = h.cancel }

    local next = function()
      if h.cancelled then
        return nil
      end
      local row = stream()
      if row == nil then
        h.cancel()
      end
      return row
    end

    return setmetatable(it, { __call = next })
  end

  return db
end

return M
