local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(matcher)
  local db = {}

  db.close = lib.noop

  db.queue = function(fn, ...)
    return fn(...)
  end

  db.search = function(ctx)
    local h = handle.new()

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
