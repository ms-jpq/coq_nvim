local T = require "coq.lib.test"
local cancel = require "coq.lib.cancel"

T.describe("cancel", function(test)
  test("cancel fires registered watchers", function()
    local token = cancel.token()
    local fired = false
    token.watch(function()
      fired = true
    end)

    token.cancel()
    T.eq(fired, true)
  end)

  test("cancel is idempotent", function()
    local token = cancel.token()
    local count = 0
    token.watch(function()
      count = count + 1
    end)

    token.cancel()
    token.cancel()
    T.eq(count, 1)
  end)

  test("watch on a cancelled token fires immediately", function()
    local token = cancel.token()
    token.cancel()

    local fired = false
    token.watch(function()
      fired = true
    end)

    T.eq(fired, true)
  end)

  test("unwatch removes a function watcher before cancel", function()
    local token = cancel.token()
    local fired = false
    local unwatch = token.watch(function()
      fired = true
    end)

    unwatch()
    token.cancel()
    T.eq(fired, false)
  end)

  test("unwatch on a cancelled token is a noop", function()
    local token = cancel.token()
    token.cancel()

    local unwatch = token.watch(function() end)
    unwatch()
  end)

  test("parent cancel cascades to child", function()
    local parent = cancel.token()
    local child = cancel.token(parent)

    parent.cancel()
    T.eq(child.cancelled, true)
  end)

  test("child cancel does not cancel parent", function()
    local parent = cancel.token()
    local child = cancel.token(parent)

    child.cancel()
    T.eq(parent.cancelled, false)
  end)

  test("child cancel releases its slot in parent watchers", function()
    local parent = cancel.token()
    local child = cancel.token(parent)

    child.cancel()

    local parent_fired = 0
    parent.watch(function()
      parent_fired = parent_fired + 1
    end)
    parent.cancel()

    T.eq(parent_fired, 1)
  end)

  test("cancel uses snapshot semantics so mid-fire unwatch is safe", function()
    local token = cancel.token()
    local count = 0
    local unwatch_late
    token.watch(function()
      count = count + 1
      unwatch_late()
    end)
    unwatch_late = token.watch(function()
      count = count + 1
    end)

    token.cancel()
    T.eq(count, 2)
  end)
end)
