local T = require "coq.lib.test"
local async = require "coq.lib.async"
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

T.describe("itertools.take_while", function(test)
  test("yields while predicate holds, stops at first false", function()
    T.eq(
      drain(itertools.take_while(function(s)
        return #s < 5
      end, from { "spot", "fido", "labrador", "rex" })),
      { "spot", "fido" }
    )
  end)

  test("predicate-false on first item yields nothing", function()
    T.eq(
      drain(itertools.take_while(function()
        return false
      end, from { "spot", "fido" })),
      {}
    )
  end)

  test("yields everything when predicate always holds", function()
    T.eq(
      drain(itertools.take_while(function()
        return true
      end, from { "spot", "fido", "rex" })),
      { "spot", "fido", "rex" }
    )
  end)

  test("empty source yields nothing", function()
    T.eq(
      drain(itertools.take_while(function()
        return true
      end, from {})),
      {}
    )
  end)

  test("does not pull past the rejected item", function()
    local pulled = 0
    local src = function()
      pulled = pulled + 1
      return pulled
    end
    drain(itertools.take_while(function(n)
      return n < 3
    end, src))
    T.eq(pulled, 3)
  end)

  test("returns nil on every call after rejection", function()
    local iter = itertools.take_while(function(n)
      return n < 2
    end, from { 1, 2, 3 })
    T.eq(iter(), 1)
    T.eq(iter(), nil)
    T.eq(iter(), nil)
  end)
end)

T.describe("itertools.intersperse", function(test)
  test("places sep between every pair of items", function()
    T.eq(drain(itertools.intersperse("/", from { "spot", "fido", "rex" })), { "spot", "/", "fido", "/", "rex" })
  end)

  test("no sep when source has a single item", function()
    T.eq(drain(itertools.intersperse("/", from { "spot" })), { "spot" })
  end)

  test("empty source yields nothing", function()
    T.eq(drain(itertools.intersperse("/", from {})), {})
  end)

  test("returns nil on every call after exhaustion", function()
    local iter = itertools.intersperse("/", from { "spot", "fido" })
    T.eq(iter(), "spot")
    T.eq(iter(), "/")
    T.eq(iter(), "fido")
    T.eq(iter(), nil)
    T.eq(iter(), nil)
  end)
end)

T.describe("itertools.chain", function(test)
  test("yields from each iterator in order", function()
    T.eq(drain(itertools.chain(from { "spot", "fido" }, from { "rex" })), { "spot", "fido", "rex" })
  end)

  test("skips an empty iterator in the middle", function()
    T.eq(drain(itertools.chain(from { "spot" }, from {}, from { "fido", "rex" })), { "spot", "fido", "rex" })
  end)

  test("all empty yields nothing", function()
    T.eq(drain(itertools.chain(from {}, from {}, from {})), {})
  end)

  test("no iterators yields nothing", function()
    T.eq(drain(itertools.chain()), {})
  end)

  test("returns nil on every call after exhaustion", function()
    local iter = itertools.chain(from { "spot" }, from { "fido" })
    T.eq(iter(), "spot")
    T.eq(iter(), "fido")
    T.eq(iter(), nil)
    T.eq(iter(), nil)
  end)
end)

T.describe("itertools.cooperative", function(test)
  test("forwards every value verbatim", function()
    async.scope(function()
      T.eq(drain(itertools.cooperative(2, from { "spot", "fido", "rex" })), { "spot", "fido", "rex" })
    end)
  end)

  test("terminates cleanly when source is exhausted", function()
    async.scope(function()
      local iter = itertools.cooperative(3, from { "spot" })
      T.eq(iter(), "spot")
      T.eq(iter(), nil)
      T.eq(iter(), nil)
    end)
  end)

  test("does not stall on an empty source", function()
    async.scope(function()
      T.eq(drain(itertools.cooperative(5, from {})), {})
    end)
  end)
end)
