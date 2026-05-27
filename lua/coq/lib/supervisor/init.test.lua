---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local async = require "coq.lib.async"
local lib = require "coq.lib"
local producer = require "coq.lib.producer"
local supervisor = require "coq.lib.supervisor"

T.describe("supervisor", function(test)
  test("merges rows from all producers", function()
    local sup = supervisor.new {
      producer.new(lib.noop, function()
        coroutine.yield "lil"
        coroutine.yield "spot"
      end),
      producer.new(lib.noop, function()
        coroutine.yield "fido"
      end),
    }
    local seen = {}
    for row in sup.search {} do
      table.insert(seen, row)
    end
    sup.close()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)

  test("new search waits for previous pump to exit", function()
    local order = {}
    local sup = supervisor.new {
      producer.new(lib.noop, function()
        async.sleep(50)
        table.insert(order, "matcher_done")
      end),
    }
    async.scope(function(n)
      n.spawn(function()
        for _ in sup.search {} do
          lib.noop()
        end
      end)
      async.sleep(5)
      sup.search({}).close()
      table.insert(order, "second_search_returned")
    end)
    sup.close()

    T.eq(order, { "matcher_done", "second_search_returned" })
  end)

  test("previous iterator returns nil after new search starts", function()
    local sup = supervisor.new {
      producer.new(lib.noop, function()
        coroutine.yield "lil"
        async.sleep(50)
        coroutine.yield "never"
      end),
    }
    local first_after, second_first
    async.scope(function(n)
      local first = sup.search {}
      n.spawn(function()
        local row1 = first()
        T.eq(row1, "lil")
        first_after = first()
      end)
      async.sleep(5)
      local second = sup.search {}
      second_first = second()
      second.close()
    end)
    sup.close()

    T.eq(first_after, nil)
    T.eq(second_first, "lil")
  end)

  test("new search cancels in-flight idle", function()
    local idle_elapsed_ms
    local sup = supervisor.new {
      producer.new(function()
        local start = vim.uv.hrtime()
        async.sleep(100)
        idle_elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      end, function()
        coroutine.yield "lil"
      end),
    }
    sup.idle {}
    async.sleep(5)
    for _ in sup.search {} do
      lib.noop()
    end
    async.sleep(20)
    sup.close()

    assert(
      idle_elapsed_ms and idle_elapsed_ms < 50,
      "idle should have been cancelled, elapsed: " .. tostring(idle_elapsed_ms)
    )
  end)

  test("idle is no-op while search is active", function()
    local idle_ran = false
    local sup = supervisor.new {
      producer.new(function()
        idle_ran = true
      end, function()
        coroutine.yield "lil"
        async.sleep(50)
      end),
    }
    local iter = sup.search {}
    iter()
    sup.idle {}
    async.sleep(10)
    iter.close()
    sup.close()

    T.eq(idle_ran, false)
  end)

  test("idle runs once search has ended", function()
    local idle_ran = false
    local sup = supervisor.new {
      producer.new(function()
        idle_ran = true
      end, function()
        coroutine.yield "lil"
      end),
    }
    for _ in sup.search {} do
      lib.noop()
    end
    sup.idle {}
    async.sleep(10)
    sup.close()

    T.eq(idle_ran, true)
  end)

  test("close tears down each producer once", function()
    local closes = {}
    local make = function(name)
      return {
        search = function()
          return setmetatable({ close = lib.noop }, {
            __call = function()
              return nil
            end,
          })
        end,
        close = function()
          closes[name] = (closes[name] or 0) + 1
        end,
      }
    end
    local sup = supervisor.new { make "a", make "b" }
    sup.close()

    T.eq(closes, { a = 1, b = 1 })
  end)

  test("producer error kills the merged stream", function()
    local sup = supervisor.new {
      producer.new(lib.noop, function()
        coroutine.yield "lil"
        error "boom"
      end),
    }
    local ok, err = pcall(function()
      for _ in sup.search {} do
        lib.noop()
      end
    end)
    sup.close()

    T.eq(ok, false)
    assert(err and tostring(err):find "boom", "expected 'boom', got: " .. tostring(err))
  end)

  test("supervisor satisfies the Producer shape (nestable)", function()
    local inner = supervisor.new {
      producer.new(lib.noop, function()
        coroutine.yield "lil"
      end),
      producer.new(lib.noop, function()
        coroutine.yield "spot"
      end),
    }
    local outer = supervisor.new {
      inner,
      producer.new(lib.noop, function()
        coroutine.yield "fido"
      end),
    }
    local seen = {}
    for row in outer.search {} do
      table.insert(seen, row)
    end
    outer.close()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)
end)
