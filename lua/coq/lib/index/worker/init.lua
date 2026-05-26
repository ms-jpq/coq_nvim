local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"

local M = {}

-- A completion source running in-process. Same shape as the threaded variant
-- (`db.queue / db.search / db.close`), but matcher runs in a coroutine on the
-- main thread, driven by the async runtime's stream primitive.
--
--   matcher(yield, ctx)    yield row tables via the supplied push fn
--
-- The same coroutine can interleave yields with async primitives (sleep,
-- await, channel pull) -- the runtime's effect-tagged yields and the
-- bare-yield stream emits are disambiguated by the driver.
--
-- State is caller-owned: matcher and any queued setup fns close over a local
-- table that lives alongside this worker. (The threaded variant stashes state
-- in the worker thread's _G instead.)
M.new = function(matcher)
  local db = {}

  db.close = lib.noop

  db.queue = function(fn, ...)
    return fn(...)
  end

  db.search = function(ctx)
    local h = handle.new()

    local pull = async.stream(function()
      pcall(matcher, coroutine.yield, ctx)
    end, h)

    local it = { close = h.cancel }

    return setmetatable(it, {
      __call = function()
        local row = pull()
        if row == nil then
          h.cancel()
        end
        return row
      end,
    })
  end

  return db
end

return M
