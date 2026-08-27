local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async._runtime"

T.describe({ "handle" }, function(test)
  test({ "watcher fires once whether registered before or after cancel" }, function()
    local h = handle.new()
    local before, after = 0, 0
    local _ = h.on_cancel(function()
      before = before + 1
    end)
    h.cancel()
    h.cancel()
    local _ = h.on_cancel(function()
      after = after + 1
    end)

    T.eq(before, 1)
    T.eq(after, 1)
  end)

  test({ "unwatch removes a function watcher before cancel" }, function()
    local h = handle.new()
    local fired = false
    local unwatch = h.on_cancel(function()
      fired = true
    end)
    unwatch()
    h.cancel()

    T.eq(fired, false)
  end)

  test({ "unwatch on a cancelled handle is a noop" }, function()
    local h = handle.new()
    h.cancel()
    local unwatch = h.on_cancel(lib.noop)
    unwatch()
  end)

  test({ "parent cancel cascades to child" }, function()
    local parent = handle.new()
    local child = handle.new(parent)
    parent.cancel()

    T.eq(child.cancelled, true)
  end)

  test({ "child cancel does not cancel parent" }, function()
    local parent = handle.new()
    local child = handle.new(parent)
    child.cancel()

    T.eq(parent.cancelled, false)
  end)

  test({ "child cancel releases its slot in parent watchers" }, function()
    local parent = handle.new()
    local child = handle.new(parent)
    child.cancel()
    local parent_fired = 0
    local _ = parent.on_cancel(function()
      parent_fired = parent_fired + 1
    end)
    parent.cancel()

    T.eq(parent_fired, 1)
  end)

  test({ "cancel uses snapshot semantics so mid-fire unwatch is safe" }, function()
    local h = handle.new()
    local count = 0
    local unwatch_a, unwatch_b
    unwatch_a = h.on_cancel(function()
      count = count + 1
      unwatch_b()
    end)
    unwatch_b = h.on_cancel(function()
      count = count + 1
      unwatch_a()
    end)
    h.cancel()

    T.eq(count, 2)
  end)

  test({ "on_cancel re-entry: watcher registers another watcher mid-fire" }, function()
    local h = handle.new()
    local fired = {}
    local _ = h.on_cancel(function()
      table.insert(fired, "outer")
      local _ = h.on_cancel(function()
        table.insert(fired, "inner")
      end)
    end)
    h.cancel()

    T.eq(fired, { "outer", "inner" })
  end)

  -- Watchers are invoked synchronously by cancel(). A watcher must not await:
  -- it can only kick off detached, fire-and-forget async work.
  test({ "cancel stays synchronous when a watcher spawns detached async work" }, function()
    local h = handle.new()
    local f = async.future()
    local order = {}

    local _ = h.on_cancel(function()
      runtime._detach(runtime.ROOT, function()
        async.sleep(-1)
        table.insert(order, "async-work")
        f.resolve()
      end)
    end)

    h.cancel()
    table.insert(order, "after-cancel")
    f.await()

    T.eq(order, { "after-cancel", "async-work" })
  end)

  -- Awaiting directly inside a watcher only "works" when cancel() happens to be
  -- driven from a coroutine, and even then it is a trap: the await suspends
  -- cancel() itself. From a synchronous caller it errors outright (yield
  -- outside a coroutine).
  test({ "awaiting directly in a watcher suspends cancel" }, function()
    local h = handle.new()
    local order = {}

    local _ = h.on_cancel(function()
      table.insert(order, "w1:before-await")
      async.sleep(-1)
      table.insert(order, "w1:after-await")
    end)

    h.cancel()
    table.insert(order, "cancel:returned")

    T.eq(order, { "w1:before-await", "w1:after-await", "cancel:returned" })
  end)
end)
