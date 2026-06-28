local T = require "coq.lib.test"
local config = require "coq.config"

T.describe({ "config.normalize" }, function(test)
  test({ "nil input round-trips" }, function()
    T.eq(config.normalize(nil), nil)
  end)

  test({ "empty table round-trips" }, function()
    T.eq(config.normalize {}, {})
  end)

  test({ "plain key passes through" }, function()
    T.eq(config.normalize { dog = "spot" }, { dog = "spot" })
  end)

  test({ "single-dot key expands one level" }, function()
    T.eq(config.normalize { ["dog.name"] = "spot" }, { dog = { name = "spot" } })
  end)

  test({ "multi-dot key expands recursively" }, function()
    T.eq(config.normalize { ["dog.name.first"] = "spot" }, { dog = { name = { first = "spot" } } })
  end)

  test({ "merges siblings under the same prefix" }, function()
    T.eq(config.normalize { ["dog.name"] = "spot", ["dog.breed"] = "lab" }, { dog = { name = "spot", breed = "lab" } })
  end)

  test({ "merges siblings under a shared multi-level prefix" }, function()
    T.eq(
      config.normalize { ["dog.name.first"] = "spot", ["dog.name.last"] = "fido" },
      { dog = { name = { first = "spot", last = "fido" } } }
    )
  end)

  test({ "merges with an existing nested table at the prefix" }, function()
    T.eq(
      config.normalize { dog = { breed = "lab" }, ["dog.name"] = "spot" },
      { dog = { breed = "lab", name = "spot" } }
    )
  end)

  test({ "recurses into nested table values" }, function()
    T.eq(config.normalize { dog = { ["name.first"] = "spot" } }, { dog = { name = { first = "spot" } } })
  end)

  test({ "recurses through dotted keys whose values are also dotted" }, function()
    T.eq(
      config.normalize { ["dog.tags"] = { ["name.first"] = "spot" } },
      { dog = { tags = { name = { first = "spot" } } } }
    )
  end)

  test({ "leaves array values alone" }, function()
    T.eq(config.normalize { ["dog.aliases"] = { "spot", "fido" } }, { dog = { aliases = { "spot", "fido" } } })
  end)

  test({ "non-string keys pass through unchanged" }, function()
    T.eq(config.normalize { [1] = "spot", [2] = "fido" }, { [1] = "spot", [2] = "fido" })
  end)

  test({ "a key with no dots stays a leaf" }, function()
    T.eq(config.normalize { ["dog"] = "spot" }, { dog = "spot" })
  end)

  test({ "does not mutate the input" }, function()
    local input = { ["dog.name"] = "spot" }
    config.normalize(input)
    T.eq(input, { ["dog.name"] = "spot" })
  end)
end)
