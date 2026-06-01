local T = require "coq.lib.test"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"

T.describe("handle", function(test)
  test("watcher fires once whether registered before or after cancel", function()
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

  test("unwatch removes a function watcher before cancel", function()
    local h = handle.new()
    local fired = false
    local unwatch = h.on_cancel(function()
      fired = true
    end)
    unwatch()
    h.cancel()

    T.eq(fired, false)
  end)

  test("unwatch on a cancelled handle is a noop", function()
    local h = handle.new()
    h.cancel()
    local unwatch = h.on_cancel(lib.noop)
    unwatch()
  end)

  test("parent cancel cascades to child", function()
    local parent = handle.new()
    local child = handle.new(parent)
    parent.cancel()

    T.eq(child.cancelled, true)
  end)

  test("child cancel does not cancel parent", function()
    local parent = handle.new()
    local child = handle.new(parent)
    child.cancel()

    T.eq(parent.cancelled, false)
  end)

  test("child cancel releases its slot in parent watchers", function()
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

  test("cancel uses snapshot semantics so mid-fire unwatch is safe", function()
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

  test("on_cancel re-entry: watcher registers another watcher mid-fire", function()
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
end)
