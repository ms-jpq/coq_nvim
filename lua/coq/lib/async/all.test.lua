local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("all", function(test)
  test("collects results in order", function()
    local out = async.all {
      function()
        async.sleep(6)
        return "lil"
      end,
      function()
        async.sleep(2)
        return "spot"
      end,
      function()
        async.sleep(4)
        return "fido"
      end,
    }

    T.eq(out, { "lil", "spot", "fido" })
  end)
end)
