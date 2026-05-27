local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"

T.describe("handle", function(test)
  test("cancel fires registered watchers", function()
    local h = handle.new()
    local fired = false
    local _ = h.on_cancel(function()
      fired = true
    end)
    h.cancel()

    T.eq(fired, true)
  end)

  test("cancel is idempotent", function()
    local h = handle.new()
    local count = 0
    local _ = h.on_cancel(function()
      count = count + 1
    end)
    h.cancel()
    h.cancel()

    T.eq(count, 1)
  end)

  test("watch on a cancelled handle fires immediately", function()
    local h = handle.new()
    h.cancel()
    local fired = false
    local _ = h.on_cancel(function()
      fired = true
    end)

    T.eq(fired, true)
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

  test("deadline cancels handle after the elapsed time", function()
    local h = handle.new(nil, 5 * T.SLOW)

    T.eq(h.cancelled, false)

    async.sleep(10 * T.SLOW)

    T.eq(h.cancelled, true)
  end)

  test("early cancel disarms the deadline timer", function()
    local h = handle.new(nil, 5 * T.SLOW)
    h.cancel()
    async.sleep(10 * T.SLOW)

    T.eq(h.cancelled, true)
  end)

  test("deadline timer is disarmed when parent already cancelled at construction", function()
    local count_live_timers = function()
      local n = 0
      vim.uv.walk(function(uv_handle)
        if uv_handle:get_type() == "timer" and not uv_handle:is_closing() then
          n = n + 1
        end
      end)
      return n
    end

    local parent = handle.new()
    parent.cancel()

    local before = count_live_timers()
    local h = handle.new(parent, 5 * T.SLOW)

    T.eq(h.cancelled, true)
    T.eq(count_live_timers(), before)
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
