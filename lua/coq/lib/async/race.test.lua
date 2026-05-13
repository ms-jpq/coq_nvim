local T = require "coq.lib.test"
local async = require "coq.lib.async"

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
end)
