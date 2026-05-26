local T = require "coq.lib.test"
local async = require "coq.lib.async"
local lib = require "coq.lib"
local producer = require "coq.lib.index.producer"

T.describe("producer (regular)", function(test)
  test("matcher yields rows that stream through the iterator", function()
    local db = producer.new(function()
      coroutine.yield "lil"
      coroutine.yield "spot"
      coroutine.yield "fido"
    end)
    local seen = {}
    for dog in db.search {} do
      table.insert(seen, dog)
    end
    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("ctx reaches the matcher unchanged", function()
    local got
    local db = producer.new(function(ctx)
      got = ctx
    end)
    -- Stream is lazy under the trampoline relay: pull once to run the matcher.
    db.search { cword = "gold" }()
    T.eq(got.cword, "gold")
  end)

  test("empty matcher returns nil on the first pull", function()
    local db = producer.new(lib.noop)
    local it = db.search {}
    T.eq(it(), nil)
  end)

  test("queue invokes the fn in-process with args", function()
    local state = { 0 }
    local db = producer.new(lib.noop)
    db.queue(function(s, n)
      s[1] = s[1] + n
    end, state, 5)
    db.queue(function(s, n)
      s[1] = s[1] + n
    end, state, 3)
    T.eq(state[1], 8)
  end)

  test("matcher composes with async primitives between yields", function()
    local db = producer.new(function()
      coroutine.yield "lil"
      async.sleep(5)
      coroutine.yield "spot"
      async.sleep(5)
      coroutine.yield "fido"
    end)
    local seen = {}
    for dog in db.search {} do
      table.insert(seen, dog)
    end
    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("iterator close stops the matcher; subsequent pulls drain then return nil", function()
    -- The channel has capacity 1, so one row may already be buffered at close;
    -- the matcher's next push fails after close, ending the coroutine.
    local db = producer.new(function()
      while true do
        coroutine.yield "row"
      end
    end)
    local it = db.search {}
    T.eq(it(), "row")
    it.close()
    while it() ~= nil do
    end
    T.eq(it(), nil)
  end)

  test("close is idempotent", function()
    local db = producer.new(function()
      coroutine.yield "lil"
    end)
    local it = db.search {}
    it.close()
    it.close() -- no error
  end)

  test("matcher error propagates to the consumer", function()
    local db = producer.new(function()
      coroutine.yield "lil"
      error "boom"
    end)
    local seen = {}
    local ok, err = pcall(function()
      for dog in db.search {} do
        table.insert(seen, dog)
      end
    end)
    T.eq(ok, false)
    T.eq(seen, { "lil" })
    assert(err and tostring(err):find "boom", "expected error to contain 'boom', got: " .. tostring(err))
  end)
end)
