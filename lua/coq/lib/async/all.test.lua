local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("all", function(test)
  test("collects results in order", function()
    local out = async.all {
      function()
        async.sleep(6 * T.SLOW)
        return "lil"
      end,
      function()
        async.sleep(2 * T.SLOW)
        return "spot"
      end,
      function()
        async.sleep(4 * T.SLOW)
        return "fido"
      end,
    }

    T.eq(out, { "lil", "spot", "fido" })
  end)
end)
