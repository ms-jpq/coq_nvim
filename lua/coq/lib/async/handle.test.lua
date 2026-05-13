local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("handle", function(test)
  test("cancel fires registered watchers", function()
    local h = async.handle()
    local fired = false
    h.watch(function()
      fired = true
    end)

    h.cancel()
    T.eq(fired, true)
  end)

  test("cancel is idempotent", function()
    local h = async.handle()
    local count = 0
    h.watch(function()
      count = count + 1
    end)

    h.cancel()
    h.cancel()
    T.eq(count, 1)
  end)

  test("watch on a cancelled handle fires immediately", function()
    local h = async.handle()
    h.cancel()

    local fired = false
    h.watch(function()
      fired = true
    end)

    T.eq(fired, true)
  end)

  test("unwatch removes a function watcher before cancel", function()
    local h = async.handle()
    local fired = false
    local unwatch = h.watch(function()
      fired = true
    end)

    unwatch()
    h.cancel()
    T.eq(fired, false)
  end)

  test("unwatch on a cancelled handle is a noop", function()
    local h = async.handle()
    h.cancel()

    local unwatch = h.watch(function() end)
    unwatch()
  end)

  test("parent cancel cascades to child", function()
    local parent = async.handle()
    local child = async.handle(parent)

    parent.cancel()
    T.eq(child.cancelled, true)
  end)

  test("child cancel does not cancel parent", function()
    local parent = async.handle()
    local child = async.handle(parent)

    child.cancel()
    T.eq(parent.cancelled, false)
  end)

  test("child cancel releases its slot in parent watchers", function()
    local parent = async.handle()
    local child = async.handle(parent)

    child.cancel()

    local parent_fired = 0
    parent.watch(function()
      parent_fired = parent_fired + 1
    end)
    parent.cancel()

    T.eq(parent_fired, 1)
  end)

  test("deadline cancels handle after the elapsed time", function()
    local h = async.handle(nil, 5)
    T.eq(h.cancelled, false)
    async.sleep(20)
    T.eq(h.cancelled, true)
  end)

  test("early cancel disarms the deadline timer", function()
    local h = async.handle(nil, 5)
    h.cancel()
    async.sleep(20)
    T.eq(h.cancelled, true)
  end)

  test("deadline fires watchers", function()
    local h = async.handle(nil, 5)
    local fired = false
    h.watch(function()
      fired = true
    end)
    async.sleep(20)
    T.eq(fired, true)
  end)

  test("cancel uses snapshot semantics so mid-fire unwatch is safe", function()
    local h = async.handle()
    local count = 0
    local unwatch_late
    h.watch(function()
      count = count + 1
      unwatch_late()
    end)
    unwatch_late = h.watch(function()
      count = count + 1
    end)

    h.cancel()
    T.eq(count, 2)
  end)
end)
