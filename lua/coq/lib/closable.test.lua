local T = require "coq.lib.test"
local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"

T.describe({ "closable.iter unwind order" }, function(test)
  test({ "defers run LIFO on natural body exit, matching lib.scope" }, function()
    local closable_order = {}
    async.scope(function()
      local close, iter = closable.iter(function(defer)
        defer(function()
          table.insert(closable_order, "a")
        end)
        defer(function()
          table.insert(closable_order, "b")
        end)
        defer(function()
          table.insert(closable_order, "c")
        end)
        coroutine.yield "spot"
      end)
      for _ in iter do
        lib.noop()
      end
      close()
    end)

    local scope_order = {}
    lib.scope(function(defer)
      defer(function()
        table.insert(scope_order, "a")
      end)
      defer(function()
        table.insert(scope_order, "b")
      end)
      defer(function()
        table.insert(scope_order, "c")
      end)
    end)

    T.eq(closable_order, { "c", "b", "a" })
    T.eq(closable_order, scope_order)
  end)

  test({ "defers run LIFO on external close, matching lib.scope" }, function()
    local closable_order = {}
    async.scope(function()
      local close, _iter = closable.iter(function(defer)
        defer(function()
          table.insert(closable_order, "a")
        end)
        defer(function()
          table.insert(closable_order, "b")
        end)
        defer(function()
          table.insert(closable_order, "c")
        end)
        coroutine.yield "spot"
      end)
      _iter()
      close()
    end)

    local scope_order = {}
    lib.scope(function(defer)
      defer(function()
        table.insert(scope_order, "a")
      end)
      defer(function()
        table.insert(scope_order, "b")
      end)
      defer(function()
        table.insert(scope_order, "c")
      end)
    end)

    T.eq(closable_order, { "c", "b", "a" })
    T.eq(closable_order, scope_order)
  end)

  test({ "close is idempotent — defers run once even if called twice" }, function()
    local runs = {}
    async.scope(function()
      local close, _iter = closable.iter(function(defer)
        defer(function()
          table.insert(runs, "x")
        end)
        coroutine.yield "spot"
      end)
      _iter()
      close()
      close()
    end)

    T.eq(runs, { "x" })
  end)

  test({ "close before any pull runs no defers (producer never entered)" }, function()
    local runs = {}
    async.scope(function()
      local close, _iter = closable.iter(function(defer)
        defer(function()
          table.insert(runs, "should-not-run")
        end)
        coroutine.yield "spot"
      end)
      close()
    end)

    T.eq(runs, {})
  end)
end)

T.describe({ "closable.iter cross-coroutine cancel" }, function(test)
  -- The iter is created in one coroutine and consumed in another (async.merge's
  -- per-producer task shape). Cancelling ONLY the consumer's subtree must still
  -- unwind the parked producer and run its defers — not deadlock the join.
  test({ "a consumer-side cancel unwinds the parked producer and runs its defers" }, function()
    local nursery = require "coq.lib.async._nursery"
    local started = async.future()
    local defer_ran, joined = false, false

    async.scope(function()
      local _close, iter = closable.iter(function(defer)
        defer(function()
          defer_ran = true
        end)
        started.resolve()
        async.future().await() -- never resolves; only a cancel ends this
      end)

      local n = nursery.new()
      n.spawn(function()
        iter() -- consumed by a DIFFERENT coroutine than the creator
      end)
      started.await() -- producer is now running under the consumer's handle

      n.cancel() -- cancel only the consumer subtree (creator is untouched)
      async.wait(200, function()
        n.join()
        joined = true
      end)
    end)

    assert(joined, "join hung: parked producer not woken by the consumer's cancel")
    assert(defer_ran, "cleanup leaked: producer defers did not run on cancel")
  end)
end)
