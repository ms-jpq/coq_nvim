local handle = require "coq.lib.async.handle"
local mpmc = require "coq.lib.channels.mpmc"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(matcher)
  local db = {}

  db.close = function() end

  db.queue = function(fn, ...)
    return fn(...)
  end

  db.search = function(ctx)
    local chan = mpmc.new(1)
    local h = handle.new()

    local yield = function(row)
      if not chan.push(row) then
        error("closed", 0)
      end
    end

    local thread = coroutine.create(function()
      pcall(matcher, yield, ctx)
      chan.close()
    end)
    runtime.bind(thread, h)
    coroutine.resume(thread)

    local closed = false
    local close = function()
      if closed then
        return
      end
      closed = true
      h.cancel()
      chan.close()
    end

    local it = { close = close }

    local next = function()
      local row = chan.pull()
      if row == nil then
        close()
      end
      return row
    end

    return setmetatable(it, { __call = next })
  end

  return db
end

return M
