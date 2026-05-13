local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.cancel"

T.describe("race", function(test)
  test("returns winning idx and value on sync task", function()
    local idx, val = async.race {
      function()
        return "woof"
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "woof")
  end)

  test("picks first task on simultaneous sync return", function()
    local idx, val = async.race {
      function()
        return "first"
      end,
      function()
        return "second"
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "first")
  end)

  test("picks fastest sleeper", function()
    local idx, val = async.race {
      function()
        async.sleep(30)
        return "slow"
      end,
      function()
        async.sleep(5)
        return "fast"
      end,
      function()
        async.sleep(60)
        return "slowest"
      end,
    }

    T.eq(idx, 2)
    T.eq(val, "fast")
  end)

  test("forwards multiple return values", function()
    local idx, a, b, c = async.race {
      function()
        return "lil", "fido", "spot"
      end,
    }

    T.eq(idx, 1)
    T.eq({ a, b, c }, { "lil", "fido", "spot" })
  end)

  test("ignores losers that finish later", function()
    local late_ran = false
    local idx, val = async.race {
      function()
        return "winner"
      end,
      function()
        async.sleep(5)
        late_ran = true
        return "loser"
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "winner")

    async.sleep(10)

    T.eq(late_ran, true)
    T.eq(idx, 1)
    T.eq(val, "winner")
  end)

  test("sync task beats later async task", function()
    local async_ran = false
    local idx = async.race {
      function() end,
      function()
        async_ran = true
        async.sleep(5)
      end,
    }

    T.eq(idx, 1)
    T.eq(async_ran, true)
  end)

  test("loser sees cancellation when a winner emerges", function()
    local loser_cancelled = false
    async.race {
      function()
        return "winner"
      end,
      function()
        async.cancellation().watch(function()
          loser_cancelled = true
        end)
        async.sleep(50)
      end,
    }

    T.eq(loser_cancelled, true)
  end)

  test("external cancel bails race with nil idx", function()
    local outer = cancel.token()
    local cancelled = false
    local idx
    async.run(function()
      idx = async.race({
        function()
          async.cancellation().watch(function()
            cancelled = true
          end)
          async.sleep(50)
        end,
      }, outer)
    end)

    outer.cancel()
    T.eq(cancelled, true)
    T.eq(idx, nil)
  end)
end)
