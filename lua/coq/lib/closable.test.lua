local T = require "coq.lib.test"
local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"

T.describe("closable.iter unwind order", function(test)
  test("defers run LIFO on natural body exit, matching lib.scope", function()
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

  test("defers run LIFO on external close, matching lib.scope", function()
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

  test("close is idempotent — defers run once even if called twice", function()
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

  test("close before any pull runs no defers (producer never entered)", function()
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
