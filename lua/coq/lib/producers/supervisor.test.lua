local T = require "coq.lib.test"
local async = require "coq.lib.async"
local config = require "coq.config"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async._nursery"
local supervisor = require "coq.lib.producers.supervisor"

---@return async.Nursery
local detached = function()
  local n = nursery.new()
  local _ = handle.new().on_cancel(n.cancel)
  return n
end

local SETTINGS = config.merged()

---@param spec { idle?: fun(ctx), matcher?: fun(_, ctx) }
---@return producers.Producer
local producer = function(spec)
  return {
    source = "mock",
    close = lib.noop,
    idle = function(_, ctx)
      if spec.idle then
        spec.idle(ctx)
      end
    end,
    search = function(_, ctx)
      local iter = async.wrap(function()
        if spec.matcher then
          spec.matcher(nil, ctx)
        end
      end)
      return lib.noop, iter
    end,
  }
end

---@param matcher fun()
---@return producers.Producer
local matcher_only = function(matcher)
  return producer { matcher = matcher }
end

---@param ... any
---@return producers.Producer
local yields = function(...)
  local items = { ... }
  return matcher_only(function()
    for _, v in ipairs(items) do
      coroutine.yield(v)
    end
  end)
end

---@param fields { idle?: fun(ctx), matcher?: fun() }
---@return producers.Producer, fun(ev: any)
local pushable = function(fields)
  local p = producer {
    idle = function(ctx)
      if fields.idle then
        fields.idle(ctx)
      end
    end,
    matcher = fields.matcher,
  }
  return p, lib.noop
end

---@param close fun()
---@param iter lib.Iterator<any>
local drain = function(close, iter)
  for _ in iter do
    lib.noop()
  end
  close()
end

T.describe({ "supervisor" }, function(test)
  test({ "closes each closable producer once" }, function()
    local closed = 0
    local p = producer {}
    p.close = function()
      closed = closed + 1
    end
    local sup = supervisor.new { p }

    sup.close()
    sup.close()

    T.eq(closed, 1)
  end)

  test({ "merges rows from all producers" }, function()
    local n = detached()
    local sup = supervisor.new { yields("lil", "spot"), yields "fido" }
    local seen = {}
    local close, iter = sup.search(SETTINGS, {})
    for row in iter do
      table.insert(seen, row)
    end
    close()
    n.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)

  test({ "new search cancels in-flight idle" }, function()
    -- pcall(sleep) returning false IS the proof idle's sleep was cancelled.
    -- If search hadn't cancelled idle, sleep would complete naturally and
    -- pcall would return true.
    local idle_started = async.future()
    local idle_cancelled = async.future()
    async.scope(function(n)
      local p, push = pushable {
        idle = function()
          idle_started.resolve()
          local ok = pcall(async.sleep, 100 * T.SLOW)
          idle_cancelled.resolve(not ok)
        end,
        matcher = function()
          coroutine.yield "lil"
        end,
      }
      local sup = supervisor.new { p }
      push(true)
      n.spawn(function()
        sup.idle(SETTINGS, {})
      end)
      idle_started.await()
      drain(sup.search(SETTINGS, {}))
    end)

    T.eq(idle_cancelled.await(), true)
  end)

  test({ "idle is no-op while search is active" }, function()
    local idle_ran = false
    async.scope(function(n)
      local sup = supervisor.new {
        producer {
          idle = function()
            idle_ran = true
          end,
          matcher = function()
            coroutine.yield "lil"
            async.sleep(50 * T.SLOW)
          end,
        },
      }
      local close, iter = sup.search(SETTINGS, {})
      iter()
      sup.idle(SETTINGS, {})
      close()
    end)

    T.eq(idle_ran, false)
  end)

  test({ "idle runs once search has ended" }, function()
    local idle_ran = async.future()
    async.scope(function(n)
      local p, push = pushable {
        idle = function()
          idle_ran.resolve()
        end,
        matcher = function()
          coroutine.yield "lil"
        end,
      }
      local sup = supervisor.new { p }
      push(true)
      drain(sup.search(SETTINGS, {}))
      sup.idle(SETTINGS, {})
      idle_ran.await()
    end)
  end)

  test({ "producer error kills the merged stream" }, function()
    local n = detached()
    local sup = supervisor.new {
      matcher_only(function()
        coroutine.yield "lil"
        error "boom"
      end),
    }
    local ok, err = pcall(function()
      drain(sup.search(SETTINGS, {}))
    end)
    n.cancel()

    T.eq(ok, false)
    assert(err and tostring(err):find "boom", "expected 'boom', got: " .. tostring(err))
  end)

  test({ "iter.close from a sibling coroutine cancels the matcher" }, function()
    local matcher_cancelled = async.future()
    local matcher_sleeping = async.future()
    local first
    async.scope(function(n)
      local sup = supervisor.new {
        matcher_only(function()
          coroutine.yield "lil"
          matcher_sleeping.resolve()
          local ok = pcall(async.sleep, 100 * T.SLOW)
          matcher_cancelled.resolve(not ok)
        end),
      }
      async.scope(function(inner)
        local close, iter = sup.search(SETTINGS, {})
        inner.spawn(function()
          first = iter()
          pcall(iter)
        end)
        matcher_sleeping.await()
        close()
        matcher_cancelled.await()
      end)
    end)

    T.eq(first, "lil")
  end)

  test({ "supervisor satisfies the Producer shape (nestable)" }, function()
    local n = detached()
    local inner = supervisor.new { yields "lil", yields "spot" }
    local outer = supervisor.new { inner, yields "fido" }
    local seen = {}
    local close, iter = outer.search(SETTINGS, {})
    for row in iter do
      table.insert(seen, row)
    end
    close()
    n.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)

  test({ "a search cancelled mid-flight lets idle run again" }, function()
    local idle_ran = false
    async.scope(function(n)
      local p = producer {
        idle = function()
          idle_ran = true
        end,
        matcher = function()
          coroutine.yield "lil"
          async.sleep(100 * T.SLOW)
        end,
      }
      local sup = supervisor.new { p }

      -- mimic subscribe_latest: consume a search, then cancel the consuming
      -- coroutine mid-flight WITHOUT calling iter.close().
      local searcher = n.spawn(function()
        local _, iter = sup.search(SETTINGS, {})
        for _ in iter do
          lib.noop()
        end
      end)
      async.sleep(5 * T.SLOW)
      searcher.cancel()
      async.sleep(5 * T.SLOW)

      sup.idle(SETTINGS, {})
    end)

    assert(idle_ran, "idle must run after a cancelled search (searching must not latch)")
  end)

  test({ "two consecutive searches without intervening idle" }, function()
    -- Real-world pattern: subscribe_latest fires two searches back-to-back.
    -- The second must produce items just like the first — searching must not
    -- latch on, and matcher state must not leak between searches.
    local items_a, items_b = {}, {}
    async.scope(function()
      local sup = supervisor.new { yields("lil", "spot") }
      do
        local close, iter = sup.search(SETTINGS, {})
        for v in iter do
          table.insert(items_a, v)
        end
        close()
      end
      do
        local close, iter = sup.search(SETTINGS, {})
        for v in iter do
          table.insert(items_b, v)
        end
        close()
      end
    end)
    T.eq(items_a, { "lil", "spot" })
    T.eq(items_b, { "lil", "spot" })
  end)

  test({ "second search proceeds after first's consumer is cancelled" }, function()
    -- subscribe_latest dispatches the next search before the previous one's
    -- consumer fully drains. The supervisor's `searching` flag must reset
    -- via the on_cancel hook so the second search's matcher is reachable.
    async.scope(function(n)
      local sup = supervisor.new { yields "lil" }

      -- Start the first search inside a cancellable task without draining.
      local searcher = n.spawn(function()
        local _, iter = sup.search(SETTINGS, {})
        for _ in iter do
          lib.noop()
        end
      end)
      async.sleep(5 * T.SLOW)
      searcher.cancel()

      -- Second search must produce items — `searching` flag must have reset.
      local close, iter = sup.search(SETTINGS, {})
      local got = {}
      for v in iter do
        table.insert(got, v)
      end
      close()
      T.eq(got, { "lil" })
    end)
  end)
end)
