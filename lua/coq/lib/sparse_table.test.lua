local T = require "coq.lib.test"
local sparse = require "coq.lib.sparse_table"

T.describe("sparse_table", function(test)
  test("push returns monotonic keys and iter yields in insertion order", function()
    local s = sparse.new()
    local k1 = s.push "lil"
    local k2 = s.push "fido"
    local k3 = s.push "spot"

    T.eq({ k1, k2, k3 }, { 1, 2, 3 })

    local out = {}
    for _, v in s.iter() do
      table.insert(out, v)
    end
    T.eq(out, { "lil", "fido", "spot" })
  end)

  test("remove leaves a hole that iter and shift skip", function()
    local s = sparse.new()
    s.push "lil"
    local k = s.push "fido"
    s.push "spot"
    s.remove(k)

    local forward = {}
    for _, v in s.iter() do
      table.insert(forward, v)
    end
    T.eq(forward, { "lil", "spot" })

    local reverse = {}
    for _, v in s.iter(true) do
      table.insert(reverse, v)
    end
    T.eq(reverse, { "spot", "lil" })

    T.eq(s.shift(), "lil")
    T.eq(s.shift(), "spot")
    T.eq(s.shift(), nil)
  end)
end)
