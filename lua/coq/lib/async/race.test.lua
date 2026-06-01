local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

T.describe("race", function(test)
  test("returns nil for empty fns list", function()
    local idx, val = async.race {}

    T.eq(idx, nil)
    T.eq(val, nil)
  end)

  test("returns as soon as winner finishes, not waiting for losers", function()
    local start = vim.uv.hrtime()
    async.race {
      function()
        async.sleep(5 * T.SLOW)
        return "fast"
      end,
      function()
        async.sleep(200 * T.SLOW)
        return "slow"
      end,
    }
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert(elapsed_ms < 100 * T.SLOW, ("expected ~5ms, got %.1fms"):format(elapsed_ms))
  end)

  test("forwards multiple return values", function()
    local idx, a, b, c = async.race {
      function()
        -- race forwards all of a winner's values; the single-T return type can't express it.
        ---@diagnostic disable-next-line: redundant-return-value
        return "lil", "fido", "spot"
      end,
    }

    T.eq(idx, 1)
    T.eq({ a, b, c }, { "lil", "fido", "spot" })
  end)

  test("losers are cancelled when a winner emerges", function()
    local late_cancelled = false
    local idx, val = async.race {
      function()
        return "winner"
      end,
      function()
        local ok = pcall(async.sleep, 5 * T.SLOW)
        late_cancelled = not ok
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "winner")
    T.eq(late_cancelled, true)
  end)

  test("sync task beats later async task", function()
    local async_ran = false
    local idx = async.race {
      lib.noop,
      function()
        async_ran = true
        async.sleep(5 * T.SLOW)
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
        local _ = runtime.current().on_cancel(function()
          loser_cancelled = true
        end)
        async.sleep(50 * T.SLOW)
      end,
    }

    T.eq(loser_cancelled, true)
  end)

  test("external cancel makes race throw cancel", function()
    local nursery = require "coq.lib.async.nursery"
    local outer = handle.new()
    local race_ok, race_err
    local n = nursery.new()
    local _ = outer.on_cancel(n.cancel)
    n.spawn(function()
      race_ok, race_err = pcall(async.race, {
        function()
          async.sleep(50 * T.SLOW)
        end,
      })
    end)
    outer.cancel()
    n.join()

    T.eq(race_ok, false)
    T.eq(cancel.is(race_err), true)
  end)

  test("child error propagates and cancels siblings", function()
    local sibling_cancelled = false
    local ok, err = pcall(function()
      async.race {
        function()
          local _ = runtime.current().on_cancel(function()
            sibling_cancelled = true
          end)
          async.sleep(100 * T.SLOW)
          return "sibling"
        end,
        function()
          async.sleep(5 * T.SLOW)
          error "child went missing"
        end,
      }
    end)

    T.eq(ok, false)
    T.eq(sibling_cancelled, true)
    assert(tostring(err):find "child went missing")
  end)
end)
