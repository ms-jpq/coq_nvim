local T = require "coq.lib.test"
local async = require "coq.lib.async"
local broadcast = require "coq.lib.channels.broadcast"

T.describe("broadcast", function(test)
  test("push without subscribers is a noop", function()
    local chan = broadcast.new()
    chan.replace "lil"
  end)

  test("replace fans out to every subscriber", function()
    local chan = broadcast.new()
    local subs = { chan.subscribe(), chan.subscribe(), chan.subscribe() }
    chan.replace "lil"

    for _, sub in ipairs(subs) do
      T.eq(sub(), "lil")
    end
  end)

  test("pull awaits a future push", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    local got

    async.scope(function(n)
      n.spawn(function()
        async.sleep(5 * T.SLOW)
        chan.replace "spot"
      end)
      got = sub()
    end)

    T.eq(got, "spot")
  end)

  test("latest push wins when subscriber is slow", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    chan.replace "lil"
    chan.replace "spot"
    chan.replace "fido"

    T.eq(sub(), "fido")
  end)

  test("subscribers iterate via for loop", function()
    local chan = broadcast.new()
    local seen = {}
    async.scope(function(n)
      n.spawn(function()
        async.sleep(2 * T.SLOW)
        chan.replace "lil"
        async.sleep(2 * T.SLOW)
        chan.replace "spot"
        async.sleep(2 * T.SLOW)
        chan.replace "fido"
      end)
      n.spawn(function()
        local iter = chan.subscribe()
        for dog in iter do
          table.insert(seen, dog)
          if #seen >= 3 then
            iter.close()
          end
        end
      end)
    end)

    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("iter.close terminates iteration", function()
    local chan = broadcast.new()
    local iter = chan.subscribe()
    local exited = false
    async.scope(function(n)
      n.spawn(function()
        for _ in iter do
        end
        exited = true
      end)
      iter.close()
    end)

    T.eq(exited, true)
  end)

  test("replace after close is silent", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    chan.close()
    chan.replace "lil"

    T.eq(sub(), nil)
  end)

  test("subscribe after close returns a closed iter", function()
    local chan = broadcast.new()
    chan.close()
    local sub = chan.subscribe()

    T.eq(sub(), nil)
  end)

  test("replace is safe when puller closes mid-iteration", function()
    local chan = broadcast.new()
    local seen_a, seen_b = {}, {}
    async.scope(function(n)
      local iter_a = chan.subscribe()
      local iter_b = chan.subscribe()
      n.spawn(function()
        for dog in iter_a do
          table.insert(seen_a, dog)
          iter_a.close()
        end
      end)
      n.spawn(function()
        for dog in iter_b do
          table.insert(seen_b, dog)
          iter_b.close()
        end
      end)
      async.sleep(2 * T.SLOW)
      chan.replace "lil"
    end)

    T.eq(seen_a, { "lil" })
    T.eq(seen_b, { "lil" })
  end)

  test("late subscriber misses prior pushes", function()
    local chan = broadcast.new()
    chan.replace "lil"
    local sub = chan.subscribe()
    async.scope(function(n)
      n.spawn(function()
        async.sleep(2 * T.SLOW)
        chan.replace "spot"
      end)
      T.eq(sub(), "spot")
    end)
  end)

  test("close drains pending value before nil", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    chan.replace "lil"
    chan.close()

    T.eq(sub(), "lil")
    T.eq(sub(), nil)
  end)

  test("iter.close before first replace cleans up without waking anything", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    sub.close()
    chan.replace "lil"

    T.eq(sub(), nil)
  end)

  test("replace returns true on success and false on closed", function()
    local chan = broadcast.new()
    T.eq(chan.replace "lil", true)
    chan.close()
    T.eq(chan.replace "spot", false)
  end)

  test("replace forwards multiple values to a subscriber", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    chan.replace("lil", "spot", "fido")

    local a, b, c = sub()
    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)
end)
