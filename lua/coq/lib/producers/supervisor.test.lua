---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local producer = require "coq.lib.producers"
local supervisor = require "coq.lib.producers.supervisor"

---@return async.Nursery
local detached = function()
  return nursery.new(handle.new())
end

T.describe("supervisor", function(test)
  test("merges rows from all producers", function()
    local n = detached()
    local sup = supervisor.new {
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "lil"
          coroutine.yield "spot"
        end,
      },
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "fido"
        end,
      },
    }
    sup.bind(n)
    local seen = {}
    for row in sup.search {} do
      table.insert(seen, row)
    end
    n.handle.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)

  test("new search waits for previous pump to exit", function()
    local order = {}
    async.scope(function(n)
      local sup = supervisor.new {
        producer.new {
          idle = lib.noop,
          bind = lib.noop,
          matcher = function()
            async.sleep(50 * T.SLOW)
            table.insert(order, "matcher_done")
          end,
        },
      }
      sup.bind(n)
      n.spawn(function()
        for _ in sup.search {} do
          lib.noop()
        end
      end)
      async.sleep(5 * T.SLOW)
      sup.search({}).close()
      table.insert(order, "second_search_returned")
    end)

    T.eq(order, { "matcher_done", "second_search_returned" })
  end)

  test("previous iterator returns nil after new search starts", function()
    local first_after, second_first
    async.scope(function(n)
      local sup = supervisor.new {
        producer.new {
          idle = lib.noop,
          bind = lib.noop,
          matcher = function()
            coroutine.yield "lil"
            async.sleep(50 * T.SLOW)
            coroutine.yield "never"
          end,
        },
      }
      sup.bind(n)
      local first = sup.search {}
      n.spawn(function()
        local row1 = first()
        T.eq(row1, "lil")
        first_after = first()
      end)
      async.sleep(5 * T.SLOW)
      local second = sup.search {}
      second_first = second()
      second.close()
    end)

    T.eq(first_after, nil)
    T.eq(second_first, "lil")
  end)

  test("new search cancels in-flight idle", function()
    local idle_elapsed_ms
    async.scope(function(n)
      local push
      local p = producer.new {
        idle = function()
          local start = vim.uv.hrtime()
          async.sleep(100 * T.SLOW)
          idle_elapsed_ms = (vim.uv.hrtime() - start) / 1e6
        end,
        matcher = function()
          coroutine.yield "lil"
        end,
        bind = function(_, p_push)
          push = p_push
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)
      push(true)
      sup.idle {}
      async.sleep(5 * T.SLOW)
      for _ in sup.search {} do
        lib.noop()
      end
      async.sleep(20 * T.SLOW)
    end)

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
      async.sleep(10 * T.SLOW)
      iter.close()
    end)

    T.eq(idle_ran, false)
  end)

  test("idle runs once search has ended", function()
    local idle_ran = false
    async.scope(function(n)
      local push
      local p = producer.new {
        idle = function()
          idle_ran = true
        end,
        matcher = function()
          coroutine.yield "lil"
        end,
        bind = function(_, p_push)
          push = p_push
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)
      for _ in sup.search {} do
        lib.noop()
      end
      push(true)
      sup.idle {}
      async.sleep(10 * T.SLOW)
    end)

    T.eq(idle_ran, true)
  end)

  test("bind cascades to each producer once", function()
    local cleanups = {}
    local make = function(name)
      return {
        search = function()
          return lib.dead_iter
        end,
        bind = function(n)
          local _ = n.handle.on_cancel(function()
            cleanups[name] = (cleanups[name] or 0) + 1
          end)
        end,
      }
    end
    local n = detached()
    local sup = supervisor.new { make "a", make "b" }
    sup.bind(n)
    n.handle.cancel()

    T.eq(cleanups, { a = 1, b = 1 })
  end)

  test("producer error kills the merged stream", function()
    local n = detached()
    local sup = supervisor.new {
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "lil"
          error "boom"
        end,
      },
    }
    sup.bind(n)
    local ok, err = pcall(function()
      for _ in sup.search {} do
        lib.noop()
      end
    end)
    n.handle.cancel()

    T.eq(ok, false)
    assert(err and tostring(err):find "boom", "expected 'boom', got: " .. tostring(err))
  end)

  test("nursery cancel is idempotent across producer cascade", function()
    local cleanups = {}
    local make = function(name)
      return {
        search = function()
          return lib.dead_iter
        end,
        bind = function(n)
          local _ = n.handle.on_cancel(function()
            cleanups[name] = (cleanups[name] or 0) + 1
          end)
        end,
      }
    end
    local n = detached()
    local sup = supervisor.new { make "a", make "b" }
    sup.bind(n)
    n.handle.cancel()
    n.handle.cancel()

    T.eq(cleanups, { a = 1, b = 1 })
  end)

  test("search after close returns a dead iter", function()
    local n = detached()
    local sup = supervisor.new {
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "lil"
        end,
      },
    }
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
      local push
      local p = producer.new {
        idle = function()
          idle_ran = true
        end,
        matcher = lib.noop,
        bind = function(_, p_push)
          push = p_push
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)
      push(true)
      n.handle.cancel()
      sup.idle {}
      async.sleep(10 * T.SLOW)
    end)

    T.eq(idle_ran, false)
  end)

  test("new idle cancels prior idle", function()
    local first_elapsed_ms
    local idle_calls = 0
    async.scope(function(n)
      local push
      local p = producer.new {
        idle = function()
          idle_calls = idle_calls + 1
          if idle_calls == 1 then
            local start = vim.uv.hrtime()
            async.sleep(100 * T.SLOW)
            first_elapsed_ms = (vim.uv.hrtime() - start) / 1e6
          end
        end,
        matcher = lib.noop,
        bind = function(_, p_push)
          push = p_push
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)

      push(true)
      sup.idle {}
      async.sleep(5 * T.SLOW)
      push(true)
      sup.idle {}
      async.sleep(20 * T.SLOW)
    end)

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
        producer.new {
          idle = lib.noop,
          bind = lib.noop,
          matcher = function()
            coroutine.yield "lil"
            async.sleep(100 * T.SLOW)
            coroutine.yield "never"
          end,
        },
      }
      sup.bind(n)
      async.scope(function(inner)
        local iter = sup.search {}
        inner.spawn(function()
          first = iter()
          after = iter()
        end)
        async.sleep(5 * T.SLOW)
        n.handle.cancel()
      end)
    end)

    T.eq(first, "lil")
    T.eq(after, nil)
  end)

  test("iter.close from a sibling coroutine cancels the matcher", function()
    local matcher_done = false
    local first, after
    async.scope(function(n)
      local sup = supervisor.new {
        producer.new {
          idle = lib.noop,
          bind = lib.noop,
          matcher = function()
            coroutine.yield "lil"
            async.sleep(100 * T.SLOW)
            matcher_done = true
          end,
        },
      }
      sup.bind(n)
      async.scope(function(inner)
        local iter = sup.search {}
        inner.spawn(function()
          first = iter()
          after = iter()
        end)
        async.sleep(5 * T.SLOW)
        iter.close()
      end)
    end)

    T.eq(first, "lil")
    T.eq(after, nil)
    T.eq(matcher_done, true)
  end)

  test("supervisor satisfies the Producer shape (nestable)", function()
    local n = detached()
    local inner = supervisor.new {
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "lil"
        end,
      },
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "spot"
        end,
      },
    }
    local outer = supervisor.new {
      inner,
      producer.new {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "fido"
        end,
      },
    }
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
