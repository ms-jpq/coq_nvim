local T = require "coq.lib.test"
local itertools = require "coq.lib.itertools"

---@param t any[]
---@return lib.Iterator<any>
local from = function(t)
  local i = 0
  return function()
    i = i + 1
    return t[i]
  end
end

---@param iter lib.Iterator<any>
---@return any[]
local drain = function(iter)
  local out = {}
  for v in iter do
    table.insert(out, v)
  end
  return out
end

T.describe("itertools.take", function(test)
  test("yields the first n elements when source is longer", function()
    T.eq(drain(itertools.take(2, from { "spot", "fido", "rex" })), { "spot", "fido" })
  end)

  test("yields all elements when source is shorter than n", function()
    T.eq(drain(itertools.take(5, from { "spot", "fido" })), { "spot", "fido" })
  end)

  test("yields nothing when source is empty", function()
    T.eq(drain(itertools.take(3, from {})), {})
  end)

  test("take(0, iter) yields nothing", function()
    T.eq(drain(itertools.take(0, from { "spot", "fido" })), {})
  end)

  test("stops pulling from the source once the cap is reached", function()
    local pulled = 0
    local src = function()
      pulled = pulled + 1
      return "labrador"
    end
    local capped = itertools.take(3, src)
    drain(capped)
    T.eq(pulled, 3)
  end)

  test("returns nil on every call after exhaustion", function()
    local capped = itertools.take(1, from { "spot", "fido" })
    T.eq(capped(), "spot")
    T.eq(capped(), nil)
    T.eq(capped(), nil)
  end)

  test("returns nil after source exhausts even with budget remaining", function()
    local capped = itertools.take(10, from { "spot" })
    T.eq(capped(), "spot")
    T.eq(capped(), nil)
    T.eq(capped(), nil)
  end)
end)

T.describe("itertools.uniq_by", function(test)
  local id = function(x)
    return x
  end

  test("drops repeats while preserving first-seen order", function()
    T.eq(drain(itertools.uniq_by(id, from { "spot", "fido", "spot", "rex", "fido" })), { "spot", "fido", "rex" })
  end)

  test("passes through when no duplicates", function()
    T.eq(drain(itertools.uniq_by(id, from { "spot", "fido", "rex" })), { "spot", "fido", "rex" })
  end)

  test("empty source yields nothing", function()
    T.eq(drain(itertools.uniq_by(id, from {})), {})
  end)

  test("dedupes by computed key, not by item identity", function()
    local items = {
      { name = "spot", breed = "labrador" },
      { name = "fido", breed = "labrador" },
      { name = "rex", breed = "boxer" },
    }
    local out = drain(itertools.uniq_by(function(d)
      return d.breed
    end, from(items)))
    T.eq(#out, 2)
    T.eq(out[1].name, "spot")
    T.eq(out[2].name, "rex")
  end)

  test("nil key bypasses dedup (every nil-key item yielded)", function()
    T.eq(
      drain(itertools.uniq_by(function()
        return nil
      end, from { "spot", "spot", "spot" })),
      { "spot", "spot", "spot" }
    )
  end)

  test("false is a valid key and dedupes", function()
    local out = drain(itertools.uniq_by(
      function(d)
        return d.good
      end,
      from {
        { name = "spot", good = false },
        { name = "fido", good = false },
        { name = "rex", good = true },
      }
    ))
    T.eq(#out, 2)
    T.eq(out[1].name, "spot")
    T.eq(out[2].name, "rex")
  end)

  test("composes with take", function()
    local out = drain(itertools.take(2, itertools.uniq_by(id, from { "spot", "spot", "fido", "rex", "fido" })))
    T.eq(out, { "spot", "fido" })
  end)
end)
