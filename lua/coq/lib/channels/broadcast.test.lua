local T = require "coq.lib.test"
local async = require "coq.lib.async"
local broadcast = require "coq.lib.channels.broadcast"

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
        for dog in chan.subscribe() do
          table.insert(seen, dog)
          if #seen >= 3 then
            n.handle.cancel()
          end
        end
      end)
    end)

    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("subscriber dropped when its handle is cancelled", function()
    local chan = broadcast.new()
    async.scope(function(n)
      n.spawn(function()
        for _ in chan.subscribe() do
        end
      end)
      n.handle.cancel()
    end)
    chan.replace "spot"
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
end)
