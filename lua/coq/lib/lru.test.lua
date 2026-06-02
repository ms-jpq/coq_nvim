local T = require "coq.lib.test"
local lru = require "coq.lib.lru"

---@param cache table
---@return table<any, any>
local snapshot = function(cache)
  local out = {}
  for k, v in lru.pairs(cache) do
    out[k] = v
  end
  return out
end

T.describe("lru", function(test)
  test("get on empty returns nil", function()
    local cache = lru.new(3)
    T.eq(cache.spot, nil)
  end)

  test("set then get returns the stored value", function()
    local cache = lru.new(3)
    cache.spot = "labrador"
    T.eq(cache.spot, "labrador")
  end)

  test("set with nil deletes the key", function()
    local cache = lru.new(3)
    cache.spot = "labrador"
    cache.spot = nil
    T.eq(cache.spot, nil)
    T.eq(snapshot(cache), {})
  end)

  test("delete on a missing key is a no-op", function()
    local cache = lru.new(2)
    cache.spot = "labrador"
    cache.fido = nil
    T.eq(snapshot(cache), { spot = "labrador" })
  end)

  test("over-capacity insert evicts the least recently used", function()
    local cache = lru.new(2)
    cache.spot = "labrador"
    cache.fido = "poodle"
    cache.rex = "boxer"

    T.eq(cache.spot, nil)
    T.eq(snapshot(cache), { fido = "poodle", rex = "boxer" })
  end)

  test("get promotes a key, sparing it from the next eviction", function()
    local cache = lru.new(2)
    cache.spot = "labrador"
    cache.fido = "poodle"
    local _ = cache.spot
    cache.rex = "boxer"

    T.eq(cache.fido, nil)
    T.eq(snapshot(cache), { spot = "labrador", rex = "boxer" })
  end)

  test("re-set existing key promotes it without growing size", function()
    local cache = lru.new(2)
    cache.spot = "labrador"
    cache.fido = "poodle"
    cache.spot = "retriever"
    cache.rex = "boxer"

    T.eq(cache.fido, nil)
    T.eq(snapshot(cache), { spot = "retriever", rex = "boxer" })
  end)

  test("repeated overflows evict in least-recent order", function()
    local cache = lru.new(3)
    cache.a = 1
    cache.b = 2
    cache.c = 3
    cache.d = 4 -- evicts a (LRU)
    cache.e = 5 -- evicts b

    T.eq(snapshot(cache), { c = 3, d = 4, e = 5 })
  end)

  test("delete then insert does not double-evict", function()
    local cache = lru.new(2)
    cache.spot = "labrador"
    cache.fido = "poodle"
    cache.spot = nil
    cache.rex = "boxer"

    T.eq(snapshot(cache), { fido = "poodle", rex = "boxer" })
  end)

  test("lru.pairs sees only live entries after eviction", function()
    local cache = lru.new(2)
    cache.spot = "labrador"
    cache.fido = "poodle"
    cache.rex = "boxer"

    local keys = {}
    for k in lru.pairs(cache) do
      keys[k] = true
    end
    T.eq(keys, { fido = true, rex = true })
  end)

  test("delete during lru.pairs leaves the rest intact", function()
    local cache = lru.new(3)
    cache.a, cache.b, cache.c = 1, 2, 3

    for k in lru.pairs(cache) do
      if k == "b" then
        cache[k] = nil
      end
    end
    T.eq(snapshot(cache), { a = 1, c = 3 })
  end)

  test("capacity = 1 keeps only the latest", function()
    local cache = lru.new(1)
    cache.spot = "labrador"
    cache.fido = "poodle"
    T.eq(snapshot(cache), { fido = "poodle" })
  end)

  test("capacity <= 0 raises", function()
    local ok = pcall(lru.new, 0)
    T.eq(ok, false)
  end)
end)
