local T = require "coq.lib.test"
local default_dict = require "coq.lib.default_dict"

T.describe({ "default_dict" }, function(test)
  test({ "seeds a missing key via the factory" }, function()
    local d = default_dict.new(function()
      return {}
    end)
    table.insert(d["lil"], "spot")
    table.insert(d["lil"], "fido")
    T.eq(d["lil"], { "spot", "fido" })
  end)

  test({ "rawsets the seeded value — repeat reads see the same instance" }, function()
    local calls = 0
    local d = default_dict.new(function()
      calls = calls + 1
      return {}
    end)
    local first = d["lil"]
    local second = d["lil"]
    assert(first == second, "expected same instance")
    T.eq(calls, 1)
  end)

  test({ "explicit set overrides the factory" }, function()
    local d = default_dict.new(function()
      return "default"
    end)
    d["lil"] = "spot"
    T.eq(d["lil"], "spot")
  end)

  test({ "pairs iterates only set keys, not the factory-default" }, function()
    local d = default_dict.new(function()
      return 0
    end)
    d["spot"] = 1
    d["fido"] = 2
    -- touching .lil via __index would seed it; we don't, so pairs ignores it.
    local keys = {}
    for k in pairs(d) do
      table.insert(keys, k)
    end
    table.sort(keys)
    T.eq(keys, { "fido", "spot" })
  end)

  test({ "counter shape: factory returns 0, increment works" }, function()
    local d = default_dict.new(function()
      return 0
    end)
    -- First access seeds 0; right-hand reads 0; left-hand writes 1.
    d["lil"] = d["lil"] + 1
    d["lil"] = d["lil"] + 1
    d["spot"] = d["spot"] + 5
    T.eq(d["lil"], 2)
    T.eq(d["spot"], 5)
  end)
end)
