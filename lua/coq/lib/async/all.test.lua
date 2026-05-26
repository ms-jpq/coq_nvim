local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("all", function(test)
  test("returns empty table for empty fns", function()
    T.eq(async.all {}, {})
  end)

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

  test("returns sync values directly", function()
    local out = async.all {
      function()
        return "woof"
      end,
      function()
        return "bark"
      end,
    }

    T.eq(out, { "woof", "bark" })
  end)
end)
