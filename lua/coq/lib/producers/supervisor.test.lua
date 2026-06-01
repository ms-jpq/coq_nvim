local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local producer = require "coq.lib.producers"
local supervisor = require "coq.lib.producers.supervisor"

---@return async.Nursery
local detached = function()
  local n = nursery.new()
  local _ = handle.new().on_cancel(n.handle.cancel)
  return n
end

---@param matcher producers.MatcherFn
---@return producers.Producer
local matcher_only = function(matcher)
  return producer.new { idle = lib.noop, bind = lib.noop, matcher = matcher }
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

---@param fields { idle?: producers.IdleFn, matcher?: producers.MatcherFn }
---@return producers.Producer, fun(ev: any)
local pushable = function(fields)
  local push
  local p = producer.new {
    idle = fields.idle or lib.noop,
    matcher = fields.matcher or lib.noop,
    bind = function(_, p_push)
      push = p_push
    end,
  }
  return p, function(ev)
    push(ev)
  end
end

---@param iter index.SearchIter
local drain = function(iter)
  for _ in iter do
    lib.noop()
  end
end

T.describe("supervisor", function(test)
  test("merges rows from all producers", function()
    local n = detached()
    local sup = supervisor.new { yields("lil", "spot"), yields "fido" }
    sup.bind(n)
    local seen = {}
    for row in sup.search {} do
      table.insert(seen, row)
    end
    n.handle.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)

  test("new search cancels previous pump", function()
    local matcher_started = async.future()
    local matcher_finished = false
    async.scope(function(n)
      local sup = supervisor.new {
        matcher_only(function()
          matcher_started.resolve()
          async.sleep(50 * T.SLOW)
          matcher_finished = true
        end),
      }
      sup.bind(n)
      n.spawn(function()
        drain(sup.search {})
      end)
      matcher_started.await()
      async.sleep(0)
      sup.search({}).close()
    end)

    T.eq(matcher_finished, false)
  end)

  test("previous iterator returns nil after new search starts", function()
    local first_after, second_first
    async.scope(function(n)
      local sup = supervisor.new {
        matcher_only(function()
          coroutine.yield "lil"
          async.sleep(50 * T.SLOW)
          coroutine.yield "never"
        end),
      }
      sup.bind(n)
      local first = sup.search {}
      local first_pulled = async.future()
      n.spawn(function()
        local row1 = first()
        T.eq(row1, "lil")
        first_pulled.resolve()
        first_after = first()
      end)
      first_pulled.await()
      local second = sup.search {}
      second_first = second()
      second.close()
    end)

    T.eq(first_after, nil)
    T.eq(second_first, "lil")
  end)

  test("new search cancels in-flight idle", function()
    local idle_started = async.future()
    local idle_finished = async.future()
    async.scope(function(n)
      local p, push = pushable {
        idle = function()
          idle_started.resolve()
          local start = vim.uv.hrtime()
          pcall(async.sleep, 100 * T.SLOW)
          idle_finished.resolve((vim.uv.hrtime() - start) / 1e6)
        end,
        matcher = function()
          coroutine.yield "lil"
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)
      push(true)
      sup.idle {}
      idle_started.await()
      drain(sup.search {})
    end)

    local idle_elapsed_ms = idle_finished.await()
    assert(
      idle_elapsed_ms and idle_elapsed_ms < 50 * T.SLOW,
      "idle should have been cancelled, elapsed: " .. tostring(idle_elapsed_ms)
    )
  end)

  test("idle is no-op while search is active", function()
    local idle_ran = false
    async.scope(function(n)
      local sup = supervisor.new {
        producer.new {
          idle = function()
            idle_ran = true
          end,
          bind = lib.noop,
          matcher = function()
            coroutine.yield "lil"
            async.sleep(50 * T.SLOW)
          end,
        },
      }
      sup.bind(n)
      local iter = sup.search {}
      iter()
      sup.idle {}
      iter.close()
    end)

    T.eq(idle_ran, false)
  end)

  test("idle runs once search has ended", function()
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
      sup.bind(n)
      drain(sup.search {})
      push(true)
      sup.idle {}
      idle_ran.await()
    end)
  end)

  test("producer error kills the merged stream", function()
    local n = detached()
    local sup = supervisor.new {
      matcher_only(function()
        coroutine.yield "lil"
        error "boom"
      end),
    }
    sup.bind(n)
    local ok, err = pcall(function()
      drain(sup.search {})
    end)
    n.handle.cancel()

    T.eq(ok, false)
    assert(err and tostring(err):find "boom", "expected 'boom', got: " .. tostring(err))
  end)

  test("bind cascades to each producer once, even on repeat cancel", function()
    local cleanups = {}
    local trace = function(name)
      return producer.new {
        idle = lib.noop,
        matcher = lib.noop,
        bind = function(n)
          local _ = n.handle.on_cancel(function()
            cleanups[name] = (cleanups[name] or 0) + 1
          end)
        end,
      }
    end
    local n = detached()
    local sup = supervisor.new { trace "a", trace "b" }
    sup.bind(n)
    n.handle.cancel()
    n.handle.cancel()

    T.eq(cleanups, { a = 1, b = 1 })
  end)

  test("search after close returns a dead iter", function()
    local n = detached()
    local sup = supervisor.new { yields "lil" }
    sup.bind(n)
    n.handle.cancel()
    local iter = sup.search {}

    T.eq(iter(), nil)
    iter.close()
  end)

  test("idle after close is a no-op", function()
    local idle_ran = false
    async.scope(function(_)
      local n = detached()
      local p, push = pushable {
        idle = function()
          idle_ran = true
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)
      push(true)
      n.handle.cancel()
      sup.idle {}
    end)

    T.eq(idle_ran, false)
  end)

  test("new idle cancels prior idle", function()
    local first_idle_started = async.future()
    local first_idle_finished = async.future()
    local second_idle_done = async.future()
    local idle_calls = 0
    async.scope(function(n)
      local p, push = pushable {
        idle = function()
          idle_calls = idle_calls + 1
          if idle_calls == 1 then
            first_idle_started.resolve()
            local start = vim.uv.hrtime()
            pcall(async.sleep, 100 * T.SLOW)
            first_idle_finished.resolve((vim.uv.hrtime() - start) / 1e6)
          else
            second_idle_done.resolve()
          end
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)

      push(true)
      sup.idle {}
      first_idle_started.await()
      push(true)
      sup.idle {}
      second_idle_done.await()
    end)

    local first_elapsed_ms = first_idle_finished.await()
    assert(
      first_elapsed_ms and first_elapsed_ms < 50 * T.SLOW,
      "first idle should have been cancelled, elapsed: " .. tostring(first_elapsed_ms)
    )
  end)

  test("close while search in-flight makes the iter return nil", function()
    local first, after
    async.scope(function(_)
      local n = detached()
      local sup = supervisor.new {
        matcher_only(function()
          coroutine.yield "lil"
          async.sleep(100 * T.SLOW)
          coroutine.yield "never"
        end),
      }
      sup.bind(n)
      async.scope(function(inner)
        local iter = sup.search {}
        local first_done = async.future()
        inner.spawn(function()
          first = iter()
          first_done.resolve()
          after = iter()
        end)
        first_done.await()
        n.handle.cancel()
      end)
    end)

    T.eq(first, "lil")
    T.eq(after, nil)
  end)

  test("iter.close from a sibling coroutine cancels the matcher", function()
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
      sup.bind(n)
      async.scope(function(inner)
        local iter = sup.search {}
        inner.spawn(function()
          first = iter()
          pcall(iter)
        end)
        matcher_sleeping.await()
        iter.close()
        matcher_cancelled.await()
      end)
    end)

    T.eq(first, "lil")
  end)

  test("supervisor satisfies the Producer shape (nestable)", function()
    local n = detached()
    local inner = supervisor.new { yields "lil", yields "spot" }
    local outer = supervisor.new { inner, yields "fido" }
    outer.bind(n)
    local seen = {}
    for row in outer.search {} do
      table.insert(seen, row)
    end
    n.handle.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)
end)
