local T = require "coq.lib.test"
local async = require "coq.lib.async"
local worker = require "coq.lib.index.worker"

T.describe("worker (regular)", function(test)
  test("matcher yields rows that stream through the iterator", function()
    local db = worker.new(function(yield)
      yield "lil"
      yield "spot"
      yield "fido"
    end)
    local seen = {}
    for dog in db.search {} do
      table.insert(seen, dog)
    end
    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("ctx reaches the matcher unchanged", function()
    local got
    local db = worker.new(function(_, ctx)
      got = ctx
    end)
    db.search { cword = "gold" }
    T.eq(got.cword, "gold")
  end)

  test("empty matcher returns nil on the first pull", function()
    local db = worker.new(function() end)
    local it = db.search {}
    T.eq(it(), nil)
  end)

  test("queue invokes the fn in-process with args", function()
    local state = { 0 }
    local db = worker.new(function() end)
    db.queue(function(s, n)
      s[1] = s[1] + n
    end, state, 5)
    db.queue(function(s, n)
      s[1] = s[1] + n
    end, state, 3)
    T.eq(state[1], 8)
  end)

  test("matcher composes with async primitives between yields", function()
    local db = worker.new(function(yield)
      yield "lil"
      async.sleep(5)
      yield "spot"
      async.sleep(5)
      yield "fido"
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
    local db = worker.new(function(yield)
      while true do
        yield "row"
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
    local db = worker.new(function(yield)
      yield "lil"
    end)
    local it = db.search {}
    it.close()
    it.close() -- no error
  end)

  test("matcher error does not propagate to the consumer", function()
    local db = worker.new(function(yield)
      yield "lil"
      error "boom"
    end)
    local seen = {}
    for dog in db.search {} do
      table.insert(seen, dog)
    end
    T.eq(seen, { "lil" })
  end)
end)
