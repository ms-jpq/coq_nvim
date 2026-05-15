local T = require "coq.lib.test"
local async = require "coq.lib.async"
local broadcast = require "coq.lib.channels.broadcast"
local handle = require "coq.lib.async.handle"

T.describe("broadcast", function(test)
  test("push without subscribers is a noop", function()
    local chan = broadcast.new()
    chan.replace "lil"
  end)

  test("subscriber receives a pushed item", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    chan.replace "lil"

    T.eq(sub(), "lil")
  end)

  test("multiple subscribers each receive the pushed item", function()
    local chan = broadcast.new()
    local a = chan.subscribe()
    local b = chan.subscribe()
    chan.replace "lil"

    T.eq(a(), "lil")
    T.eq(b(), "lil")
  end)

  test("pull awaits a future push", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    local got

    async.scope(function(n)
      n.spawn(function()
        async.sleep(5)
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
        async.sleep(2)
        chan.replace "lil"
        async.sleep(2)
        chan.replace "spot"
        async.sleep(2)
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

  test("chan-level handle cancel terminates iteration", function()
    local h = handle.new()
    local chan = broadcast.new(h)
    local seen = {}
    async.scope(function(n)
      n.spawn(function()
        async.sleep(2)
        chan.replace "lil"
        async.sleep(2)
        h.cancel()
        async.sleep(2)
        chan.replace "spot"
      end)
      n.spawn(function()
        for dog in chan.subscribe() do
          table.insert(seen, dog)
        end
      end)
    end)

    T.eq(seen, { "lil" })
  end)

  test("new with already-cancelled handle yields a closed channel", function()
    local h = handle.new()
    h.cancel()
    local chan = broadcast.new(h)
    local seen = {}
    async.scope(function(n)
      n.spawn(function()
        for dog in chan.subscribe() do
          table.insert(seen, dog)
        end
      end)
      chan.replace "lil"
    end)

    T.eq(seen, {})
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
      async.sleep(2)
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
        async.sleep(2)
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

  test("replace fans out to many subscribers in one pass", function()
    local chan = broadcast.new()
    local subs = {}
    for i = 1, 5 do
      subs[i] = chan.subscribe()
    end
    chan.replace "lil"

    for i = 1, 5 do
      T.eq(subs[i](), "lil")
    end
  end)

  test("iter.close before first replace cleans up without waking anything", function()
    local chan = broadcast.new()
    local sub = chan.subscribe()
    sub.close()
    chan.replace "lil"

    T.eq(sub(), nil)
  end)
end)
