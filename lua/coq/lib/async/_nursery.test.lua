local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async._nursery"
local runtime = require "coq.lib.async._runtime"

T.describe("nursery", function(test)
  test("join awaits all spawned children", function()
    local n = nursery.new()
    local count = 0
    n.spawn(function()
      async.sleep(2 * T.SLOW)
      count = count + 1
    end)
    n.spawn(function()
      async.sleep(5 * T.SLOW)
      count = count + 1
    end)
    n.join()

    T.eq(count, 2)
  end)

  test("join throws cancel when ambient cancelled mid-join", function()
    local outer = handle.new()
    local join_ok, join_err
    local n = nursery.new()
    local _ = outer.on_cancel(n.cancel)
    n.spawn(function()
      local inner = nursery.new()
      inner.spawn(function()
        async.sleep(200 * T.SLOW)
      end)
      join_ok, join_err = pcall(inner.join)
    end)
    n.spawn(function()
      async.sleep(5 * T.SLOW)
      outer.cancel()
    end)
    n.join()

    T.eq(join_ok, false)
    T.eq(cancel.is(join_err), true)
  end)

  test("join throws cancel on joiner cancel even when child hangs", function()
    local outer = handle.new()
    local join_ok, join_err
    local n = nursery.new()
    local _ = outer.on_cancel(n.cancel)
    n.spawn(function()
      local inner = nursery.new()
      inner.spawn(function()
        local f = async.future()
        f.await()
      end)
      join_ok, join_err = pcall(inner.join)
    end)
    n.spawn(function()
      async.sleep(5 * T.SLOW)
      outer.cancel()
    end)
    n.join()

    T.eq(join_ok, false)
    T.eq(cancel.is(join_err), true)
  end)

  test("spawn after join raises", function()
    local n = nursery.new()
    n.join()

    local ok, err = pcall(n.spawn, lib.noop)
    T.eq(ok, false)
    assert(tostring(err):find "nursery is closed")
  end)

  test("spawn fires defers in reverse order on normal exit", function()
    local n = nursery.new()
    local order = {}
    n.spawn(function(defer)
      defer(function()
        table.insert(order, "first registered")
      end)
      defer(function()
        table.insert(order, "second registered")
      end)
      table.insert(order, "body")
    end)
    n.join()

    T.eq(order, { "body", "second registered", "first registered" })
  end)

  test("spawn fires defers even when body errors", function()
    local n = nursery.new()
    local fired = false
    n.spawn(function(defer)
      defer(function()
        fired = true
      end)
      error "lil went missing"
    end)
    local ok, err = pcall(n.join)

    T.eq(ok, false)
    T.eq(fired, true)
    assert(err:find "lil went missing")
  end)

  test("join surfaces spawn errors even when joiner is cancelled mid-await", function()
    local outer = handle.new()
    local n = nursery.new()
    local join_ok, join_err

    async.scope(function(test_n)
      test_n.spawn(function()
        runtime.bind(coroutine.running(), outer)

        -- spot errors at t=20*SLOW, populating n.errors=["spot ran off"]
        -- and triggering n.h.cancel.
        n.spawn(function()
          async.sleep(20 * T.SLOW)
          error "spot ran off"
        end)

        -- cancel=false keeps block parked past n.h.cancel cascading, so
        -- pending stays non-empty when the joiner enters n.join.
        n.spawn(function()
          local block = async.future()
          block.await { cancel = false }
        end)

        async.sleep(40 * T.SLOW)
        outer.cancel()
        join_ok, join_err = pcall(n.join)
      end)
    end)

    T.eq(join_ok, false)
    assert(tostring(join_err):find "spot ran off", "expected spot ran off, got: " .. tostring(join_err))
  end)

  test("join raises error group when multiple children error", function()
    local n = nursery.new()
    n.spawn(function()
      async.sleep(-1)
      error "first"
    end)
    n.spawn(function()
      pcall(async.sleep, 50 * T.SLOW)
      error "second"
    end)

    local ok, err = pcall(n.join)
    T.eq(ok, false)
    T.eq(#err.errs, 2)
    assert(tostring(err.errs[1]):find "first")
    assert(tostring(err.errs[2]):find "second")
  end)
end)

T.describe("scope", function(test)
  test("joins spawned tasks before returning", function()
    local count = 0
    async.scope(function(n)
      n.spawn(function()
        async.sleep(2 * T.SLOW)
        count = count + 1
      end)
      n.spawn(function()
        async.sleep(5 * T.SLOW)
        count = count + 1
      end)
    end)

    T.eq(count, 2)
  end)

  test("cancels and re-raises on body error", function()
    local cancelled = false
    local ok, err = pcall(function()
      async.scope(function(n)
        n.spawn(function()
          local _ = runtime.current().on_cancel(function()
            cancelled = true
          end)
          async.sleep(100 * T.SLOW)
        end)
        async.sleep(0)
        error "body went sideways"
      end)
    end)

    T.eq(ok, false)
    T.eq(cancelled, true)
    assert(tostring(err):find "body went sideways")
  end)

  test("cancels and re-raises on child error", function()
    local sibling_cancelled = false
    local ok, err = pcall(function()
      async.scope(function(n)
        n.spawn(function()
          local _ = runtime.current().on_cancel(function()
            sibling_cancelled = true
          end)
          async.sleep(100 * T.SLOW)
        end)
        n.spawn(function()
          async.sleep(5 * T.SLOW)
          error "child went missing"
        end)
      end)
    end)

    T.eq(ok, false)
    T.eq(sibling_cancelled, true)
    assert(tostring(err):find "child went missing")
  end)
end)
