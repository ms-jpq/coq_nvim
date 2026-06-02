local T = require "coq.lib.test"
local async = require "coq.lib.async"
local buf_tracker = require "coq.lib.producers.buf_tracker"

---@class trace.Spec
---@field fetches { buf: integer, prev_tick?: integer }[]
---@field prunes integer[]
---@field reindexes any[]

---@param overrides? table
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
    reindex = function(metas)
      for _, meta in pairs(metas) do
        table.insert(reindexes, meta)
      end
    end,
    prune = function(buf)
      table.insert(prunes, buf)
    end,
  }
  return tracker, { fetches = fetches, prunes = prunes, reindexes = reindexes }
end

---@param updated integer[]?
---@param removed integer[]?
---@return idle.Ctx
local idle_ctx = function(updated, removed)
  local u, r = {}, {}
  for _, b in pairs(updated or {}) do
    u[b] = true
  end
  for _, b in pairs(removed or {}) do
    r[b] = true
  end
  return {
    ---@diagnostic disable-next-line: missing-fields
    ctx = {},
    updated = u,
    removed = r,
  } --[[@as idle.Ctx]]
end

T.describe("buf_tracker", function(test)
  test("update prunes, reindexes once for each new buf", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx { 7 })
    end)

    T.eq(trace.fetches, { { buf = 7, prev_tick = nil } })
    T.eq(trace.prunes, { 7 })
    T.eq(#trace.reindexes, 1)
    T.eq(trace.reindexes[1].buf, 7)
  end)

  test("update with unchanged tick (fetch returns nil) is a no-op", function()
    local tracker, trace = mk {
      fetch = function()
        return nil
      end,
    }

    async.scope(function()
      tracker(idle_ctx { 7 })
    end)

    T.eq(#trace.fetches, 1)
    T.eq(trace.prunes, {})
    T.eq(trace.reindexes, {})
  end)

  test("remove prunes", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx({ 7 }, nil))
      tracker(idle_ctx(nil, { 7 }))
    end)

    T.eq(trace.prunes, { 7, 7 })
  end)

  test("second update forwards prior tick as prev_tick", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx { 7 })
      tracker(idle_ctx { 7 })
    end)

    T.eq(trace.fetches, {
      { buf = 7, prev_tick = nil },
      { buf = 7, prev_tick = 1 },
    })
  end)

  test("mixed batch handles each buf independently", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx({ 1, 3 }, { 2 }))
    end)

    local seen_bufs = {}
    for _, f in ipairs(trace.fetches) do
      seen_bufs[f.buf] = true
    end
    T.eq(seen_bufs, { [1] = true, [3] = true })
    T.eq(trace.prunes[#trace.prunes - 1] ~= nil and trace.prunes[#trace.prunes] ~= nil, true)
  end)

  test("remove without prior update still prunes", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx(nil, { 99 }))
    end)

    T.eq(trace.prunes, { 99 })
    T.eq(trace.reindexes, {})
  end)

  test("concurrent updates with same prev_tick: only first reindexes", function()
    local tracker, trace = mk {
      fetch = function(buf, _)
        async.sleep(0)
        return { buf = buf, tick = 1, payload = "labrador" }
      end,
    }

    async.scope(function(n)
      n.spawn(function()
        tracker(idle_ctx { 7 })
      end)
      n.spawn(function()
        tracker(idle_ctx { 7 })
      end)
    end)

    T.eq(#trace.fetches, 2)
    T.eq(#trace.prunes, 1)
    T.eq(#trace.reindexes, 1)
  end)
end)
