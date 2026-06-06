local T = require "coq.lib.test"
local async = require "coq.lib.async"
local mpmc = require "coq.lib.channels.mpmc"

T.describe("mpmc", function(test)
  test("push then pull returns the value", function()
    local chan = mpmc.new(1)
    chan.push "lil"

    T.eq(chan.pull(), "lil")
  end)

  test("pulls in FIFO order", function()
    local chan = mpmc.new(3)
    chan.push "lil"
    chan.push "spot"
    chan.push "fido"

    T.eq(chan.pull(), "lil")
    T.eq(chan.pull(), "spot")
    T.eq(chan.pull(), "fido")
  end)

  test("pull blocks until push happens", function()
    local chan = mpmc.new(1)
    local got
    async.scope(function(n)
      n.spawn(function()
        async.sleep(5 * T.SLOW)
        chan.push "spot"
      end)
      got = chan.pull()
    end)

    T.eq(got, "spot")
  end)

  test("push and pull forward multiple values", function()
    local chan = mpmc.new(1)
    chan.push("lil", "spot", "fido")
    local a, b, c = chan.pull()

    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)

  test("close on empty makes pull return nil", function()
    local chan = mpmc.new(1)
    chan.close()

    T.eq(chan.pull(), nil)
  end)

  test("close drains queued items before nil", function()
    local chan = mpmc.new(2)
    chan.push "lil"
    chan.push "spot"
    chan.close()

    T.eq(chan.pull(), "lil")
    T.eq(chan.pull(), "spot")
    T.eq(chan.pull(), nil)
  end)

  test("push after close is silently dropped", function()
    local chan = mpmc.new(1)
    chan.close()
    chan.push "lil"

    T.eq(chan.pull(), nil)
  end)

  test("push returns true on success and false on closed", function()
    local chan = mpmc.new(1)

    T.eq(chan.push "lil", true)
    chan.close()
    T.eq(chan.push "spot", false)
  end)

  test("close wakes a blocked puller", function()
    local chan = mpmc.new(1)
    local got
    async.scope(function(n)
      n.spawn(function()
        got = chan.pull()
      end)
      async.sleep(5 * T.SLOW)
      chan.close()
    end)

    T.eq(got, nil)
  end)

  test("multiple producers push from coroutines", function()
    local chan = mpmc.new(1)
    local seen = {}
    async.scope(function(n)
      n.spawn(function()
        for _ = 1, 3 do
          local v = chan.pull()
          if v == nil then
            break
          end
          table.insert(seen, v)
        end
      end)
      n.spawn(function()
        async.sleep(2 * T.SLOW)
        chan.push "lil"
      end)
      n.spawn(function()
        async.sleep(4 * T.SLOW)
        chan.push "spot"
      end)
      n.spawn(function()
        async.sleep(6 * T.SLOW)
        chan.push "fido"
      end)
    end)

    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("bounded push blocks until pull frees a slot", function()
    local chan = mpmc.new(2)
    local progress = {}
    async.scope(function(n)
      n.spawn(function()
        chan.push "lil"
        table.insert(progress, "p1")
        chan.push "spot"
        table.insert(progress, "p2")
        chan.push "fido"
        table.insert(progress, "p3")
      end)
      n.spawn(function()
        async.sleep(5 * T.SLOW)
        table.insert(progress, "pull")
        chan.pull()
      end)
    end)

    T.eq(progress, { "p1", "p2", "pull", "p3" })
  end)

  test("bounded wakes producers one slot at a time", function()
    local chan = mpmc.new(1)
    local pushed = {}
    async.scope(function(n)
      for _, dog in ipairs { "lil", "spot", "fido" } do
        n.spawn(function()
          chan.push(dog)
          table.insert(pushed, dog)
        end)
      end
      async.sleep(2 * T.SLOW)
      T.eq(#pushed, 1)
      chan.pull()
      async.sleep(2 * T.SLOW)
      T.eq(#pushed, 2)
      chan.pull()
      async.sleep(2 * T.SLOW)
      T.eq(#pushed, 3)
      chan.pull()
    end)
  end)

  test("callable via for-loop", function()
    local chan = mpmc.new(1)
    local seen = {}
    async.scope(function(n)
      n.spawn(function()
        for v in chan.pull do
          table.insert(seen, v)
        end
      end)
      n.spawn(function()
        chan.push "lil"
        chan.push "spot"
        chan.push "fido"
        chan.close()
      end)
    end)

    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("push synchronously hands off to a waiting puller", function()
    local chan = mpmc.new(1)
    local order = {}
    async.scope(function(n)
      n.spawn(function()
        table.insert(order, "pull_start")
        chan.pull()
        table.insert(order, "pull_done")
      end)
      async.sleep(2 * T.SLOW)
      table.insert(order, "push_start")
      chan.push "lil"
      table.insert(order, "push_done")
    end)

    T.eq(order, { "pull_start", "push_start", "pull_done", "push_done" })
  end)

  test("bounded close wakes all blocked pushers", function()
    local chan = mpmc.new(1)
    local results = {}
    async.scope(function(n)
      n.spawn(function()
        chan.push "lil"
        results.a = chan.push "spot"
      end)
      n.spawn(function()
        results.b = chan.push "fido"
      end)
      async.sleep(5 * T.SLOW)
      chan.close()
    end)

    T.eq(results, { a = false, b = false })
  end)

  test("a cancelled puller does not swallow a later push", function()
    local chan = mpmc.new(1)
    local got = "none"
    async.scope(function(n)
      local a = n.spawn(function()
        chan.pull()
      end)
      n.spawn(function()
        got = chan.pull()
      end)
      async.sleep(3 * T.SLOW)
      a.cancel()
      async.sleep(3 * T.SLOW)
      chan.push "spot"
    end)

    T.eq(got, "spot")
  end)
end)
