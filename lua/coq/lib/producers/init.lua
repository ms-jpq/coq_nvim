local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

---@class producers.Producer
---@field search fun(ctx: index.SearchContext): table
---@field idle fun(ctx: index.SearchContext)
---@field close fun()
---@field queue function

---@alias producers.NewProducer fun(idle: fun(ctx: index.SearchContext), matcher: fun(ctx: index.SearchContext)): producers.Producer

local M = {}

---@type producers.NewProducer
M.new = function(idle, matcher)
  local db = { close = lib.noop, idle = idle }

  db.queue = function(fn, ...)
    return fn(...)
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
