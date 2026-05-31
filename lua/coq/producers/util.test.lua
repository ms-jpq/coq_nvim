local T = require "coq.lib.test"
local util = require "coq.producers.util"

T.describe("util.dedup", function(test)
  test("keeps first occurrence, drops repeats by key", function()
    local items = { { w = "spot" }, { w = "fido" }, { w = "spot" }, { w = "rex" }, { w = "fido" } }
    local i = 0
    local iter = function()
      i = i + 1
      return items[i]
    end
    local out = {}
    for it in
      util.dedup(iter, function(x)
        return x.w
      end)
    do
      table.insert(out, it.w)
    end
    T.eq(out, { "spot", "fido", "rex" })
  end)

  test("empty iter yields nothing", function()
    local out = {}
    for it in
      util.dedup(function()
        return nil
      end, function(x)
        return x
      end)
    do
      table.insert(out, it)
    end
    T.eq(out, {})
  end)
end)
