local T = require "coq.lib.test"
local async = require "coq.lib.async"
local buf_tracker = require "coq.lib.producers.buf_tracker"

---@class trace.Spec
---@field fetches { buf: integer, prev_tick?: integer }[]
---@field prunes integer[]
---@field reindexes any[]

---@param overrides? table
---@return buf_tracker.Tracker, trace.Spec
local mk = function(overrides)
  overrides = overrides or {}
  local fetches, prunes, reindexes = {}, {}, {}

  local default_fetch = function(buf, prev_tick)
    return { buf = buf, tick = (prev_tick or 0) + 1, payload = "labrador" }
  end

  local tracker = buf_tracker.new {
    fetch = function(buf, prev_tick)
      table.insert(fetches, { buf = buf, prev_tick = prev_tick })
      return (overrides.fetch or default_fetch)(buf, prev_tick)
    end,
    reindex = function(meta)
      table.insert(reindexes, meta)
    end,
    prune = function(buf)
      table.insert(prunes, buf)
    end,
  }
  return tracker, { fetches = fetches, prunes = prunes, reindexes = reindexes }
end

T.describe("buf_tracker", function(test)
  test("update event prunes, reindexes, and bumps last_tick", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker.idle(nil, { [7] = { kind = "update" } })
    end)

    T.eq(trace.fetches, { { buf = 7, prev_tick = nil } })
    T.eq(trace.prunes, { 7 })
    T.eq(#trace.reindexes, 1)
    T.eq(trace.reindexes[1].buf, 7)
    T.eq(tracker.state.last_tick, { [7] = 1 })
  end)

  test("update with unchanged tick (fetch returns nil) is a no-op", function()
    local tracker, trace = mk {
      fetch = function()
        return nil
      end,
    }

    async.scope(function()
      tracker.idle(nil, { [7] = { kind = "update" } })
    end)

    T.eq(#trace.fetches, 1)
    T.eq(trace.prunes, {})
    T.eq(trace.reindexes, {})
    T.eq(tracker.state.last_tick, {})
  end)

  test("remove event prunes and clears last_tick", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker.idle(nil, { [7] = { kind = "update" } })
      tracker.idle(nil, { [7] = { kind = "remove" } })
    end)

    T.eq(trace.prunes, { 7, 7 })
    T.eq(tracker.state.last_tick, {})
  end)

  test("second update forwards prior tick as prev_tick", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker.idle(nil, { [7] = { kind = "update" } })
      tracker.idle(nil, { [7] = { kind = "update" } })
    end)

    T.eq(trace.fetches, {
      { buf = 7, prev_tick = nil },
      { buf = 7, prev_tick = 1 },
    })
    T.eq(tracker.state.last_tick, { [7] = 2 })
  end)

  test("mixed batch handles each buf independently", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker.idle(nil, {
        [1] = { kind = "update" },
        [2] = { kind = "remove" },
        [3] = { kind = "update" },
      })
    end)

    local seen_bufs = {}
    for _, f in ipairs(trace.fetches) do
      seen_bufs[f.buf] = true
    end
    T.eq(seen_bufs, { [1] = true, [3] = true })
    T.eq(tracker.state.last_tick, { [1] = 1, [3] = 1 })
  end)

  test("remove without prior update still prunes", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker.idle(nil, { [99] = { kind = "remove" } })
    end)

    T.eq(trace.prunes, { 99 })
    T.eq(trace.reindexes, {})
    T.eq(tracker.state.last_tick, {})
  end)

  test("fetch returning nil after a prior update keeps last_tick intact", function()
    local first = true
    local tracker, _ = mk {
      fetch = function(buf)
        if first then
          first = false
          return { buf = buf, tick = 42 }
        end
        return nil
      end,
    }

    async.scope(function()
      tracker.idle(nil, { [7] = { kind = "update" } })
      tracker.idle(nil, { [7] = { kind = "update" } })
    end)

    T.eq(tracker.state.last_tick, { [7] = 42 })
  end)
end)
