local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"

T.describe("event", function(test)
  test("wait returns immediately when already set", function()
    local e = async.event()
    e.set()

    T.eq(e.is_set(), true)
    e.wait()
  end)

  test("wait blocks until set", function()
    local e = async.event()
    local woke = false
    async.scope(function(n)
      n.spawn(function()
        e.wait()
        woke = true
      end)
      n.spawn(function()
        async.sleep(5)
        e.set()
      end)
    end)

    T.eq(woke, true)
  end)

  test("set wakes all waiters", function()
    local e = async.event()
    local count = 0
    async.scope(function(n)
      for _ = 1, 3 do
        n.spawn(function()
          e.wait()
          count = count + 1
        end)
      end
      n.spawn(function()
        async.sleep(5)
        e.set()
      end)
    end)

    T.eq(count, 3)
  end)

  test("set is idempotent", function()
    local e = async.event()
    e.set()
    e.set()

    T.eq(e.is_set(), true)
  end)

  test("wait returns when explicit handle cancelled", function()
    local h = handle.new()
    local woke = false
    async.scope(h, function(n)
      n.spawn(function()
        local e = async.event()
        e.wait(runtime.current())
        woke = true
      end)
      async.sleep(5)
      h.cancel()
    end)

    T.eq(woke, true)
  end)

  test("wait without handle ignores ambient cancel", function()
    local h = handle.new()
    local woke = false
    async.scope(h, function(n)
      n.spawn(function()
        local e = async.event()
        n.handle.on_cancel(e.set)
        e.wait()
        woke = true
      end)
      async.sleep(5)
      h.cancel()
    end)

    T.eq(woke, true)
  end)
end)
