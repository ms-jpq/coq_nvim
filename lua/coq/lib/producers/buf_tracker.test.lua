local T = require "coq.lib.test"
local async = require "coq.lib.async"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local config = require "coq.config"

local SETTINGS = config.merged()

---@class trace.Spec
---@field fetches { buf: integer, prev_tick?: integer }[]
---@field prunes integer[]
---@field reindexes any[]

---@param overrides? table
local mk = function(overrides)
  overrides = overrides or {}
  local fetches, prunes, reindexes = {}, {}, {}

  local default_compare = function(buf, previous)
    local prev_tick = previous and previous.tick
    return { buf = buf, tick = (prev_tick or 0) + 1, payload = "labrador" }
  end

  local settings_seen = {}
  local tracker = buf_tracker.new {
    compare = function(buf, previous)
      table.insert(fetches, { buf = buf, prev_tick = previous and previous.tick })
      return (overrides.compare or default_compare)(buf, previous)
    end,
    index = function(_, metas)
      table.insert(settings_seen, SETTINGS)
      for _, meta in pairs(metas) do
        table.insert(reindexes, meta)
      end
    end,
    prune = function(_, stale)
      table.insert(settings_seen, SETTINGS)
      for buf, meta in pairs(stale) do
        table.insert(prunes, { buf = buf, meta = meta })
      end
    end,
  }
  return tracker, { fetches = fetches, prunes = prunes, reindexes = reindexes, settings_seen = settings_seen }
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
    cache_dir = "/tmp",
    updated = u,
    removed = r,
  } --[[@as idle.Ctx]]
end

T.describe("buf_tracker", function(test)
  test("first-time update reindexes, does not prune (no prior state)", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx { 7 })
    end)

    T.eq(trace.fetches, { { buf = 7, prev_tick = nil } })
    T.eq(trace.prunes, {})
    T.eq(#trace.reindexes, 1)
    T.eq(trace.reindexes[1].buf, 7)
    T.eq(trace.settings_seen, { SETTINGS, SETTINGS })
  end)

  test("update with unchanged tick (compare returns nil) is a no-op", function()
    local tracker, trace = mk {
      compare = function()
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

  test("remove after prior update prunes with the prior meta", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx({ 7 }, nil))
      tracker(idle_ctx(nil, { 7 }))
    end)

    T.eq(#trace.prunes, 1)
    T.eq(trace.prunes[1].buf, 7)
    T.eq(trace.prunes[1].meta.buf, 7)
    T.eq(trace.prunes[1].meta.tick, 1)
  end)

  test("second update prunes prior meta and forwards prior tick", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx { 7 })
      tracker(idle_ctx { 7 })
    end)

    T.eq(trace.fetches, {
      { buf = 7, prev_tick = nil },
      { buf = 7, prev_tick = 1 },
    })
    T.eq(#trace.prunes, 1)
    T.eq(trace.prunes[1].meta.tick, 1)
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
    T.eq(trace.prunes, {})
  end)

  test("remove without prior update is a no-op", function()
    local tracker, trace = mk()

    async.scope(function()
      tracker(idle_ctx(nil, { 99 }))
    end)

    T.eq(trace.prunes, {})
    T.eq(trace.reindexes, {})
  end)

  -- a run cancelled during index must NOT advance state, so the carried-over buf
  -- is recomputed (and re-indexed) on the next run rather than skipped forever.
  test("a cancelled index leaves state uncommitted so the buf is recomputed", function()
    local prev_ticks, fail = {}, true
    local tracker = buf_tracker.new {
      compare = function(_, previous)
        table.insert(prev_ticks, previous and previous.tick or 0)
        return { tick = (previous and previous.tick or 0) + 1 }
      end,
      prune = function() end,
      index = function(_, computed)
        if fail and next(computed) then
          fail = false
          error "index cancelled"
        end
      end,
    }

    async.scope(function()
      pcall(tracker, idle_ctx { 7 }) -- index throws → state[7] not committed
      tracker(idle_ctx { 7 }) -- retried (the idle carry re-delivers buf 7)
    end)

    -- run 2's compare sees prev=0: the cancelled run advanced nothing
    T.eq(prev_ticks, { 0, 0 })
  end)
end)
