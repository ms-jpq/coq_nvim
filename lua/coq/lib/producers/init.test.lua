local T = require "coq.lib.test"
local async = require "coq.lib.async"
local lib = require "coq.lib"
local producer = require "coq.lib.producers"

T.describe("producer (regular)", function(test)
  test("ctx reaches the matcher unchanged", function()
    local got
    local db = producer.new {
      idle = lib.noop,
      bind = lib.noop,
      matcher = function(_, ctx)
        got = ctx
      end,
    }
    -- Stream is lazy under the trampoline relay: pull once to run the matcher.
    db.search { cword = "gold" }()
    T.eq(got.cword, "gold")
  end)

  test("empty matcher returns nil on the first pull", function()
    local db = producer.new { idle = lib.noop, bind = lib.noop, matcher = lib.noop }
    local it = db.search {}
    T.eq(it(), nil)
  end)

  test("matcher composes with async primitives between yields", function()
    local db = producer.new {
      idle = lib.noop,
      bind = lib.noop,
      matcher = function()
        coroutine.yield "lil"
        async.sleep(5 * T.SLOW)
        coroutine.yield "spot"
        async.sleep(5 * T.SLOW)
        coroutine.yield "fido"
      end,
    }
    local seen = {}
    for dog in db.search {} do
      table.insert(seen, dog)
    end
    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("matcher error propagates to the consumer", function()
    local db = producer.new {
      idle = lib.noop,
      bind = lib.noop,
      matcher = function()
        coroutine.yield "lil"
        error "boom"
      end,
    }
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
