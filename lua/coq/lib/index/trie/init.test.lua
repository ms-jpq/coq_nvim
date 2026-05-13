local T = require "coq.lib.test"
local trie = require "coq.lib.index.trie"

local collect = function(iter)
  local out = {}
  for k, v in iter do
    out[k] = v
  end
  return out
end

T.describe("trie", function(test)
  test("insert then get round-trips", function()
    local t = trie.new()
    t.insert("lil", "good")

    T.eq(t.get "lil", "good")
  end)

  test("get on missing key returns nil", function()
    local t = trie.new()
    t.insert("lil", "good")

    T.eq(t.get "spot", nil)
  end)

  test("get on internal node without value returns nil", function()
    local t = trie.new()
    t.insert("lil", "good")

    T.eq(t.get "re", nil)
  end)

  test("get on extension past a terminal returns nil", function()
    local t = trie.new()
    t.insert("lil", "good")

    T.eq(t.get "lilx", nil)
  end)

  test("insert overwrites previous value", function()
    local t = trie.new()
    t.insert("lil", "good")
    t.insert("lil", "bad")

    T.eq(t.get "lil", "bad")
  end)

  test("stores keys where one is a prefix of another", function()
    local t = trie.new()
    t.insert("lil", "dog")
    t.insert("lilx", "puppy")

    T.eq(t.get "lil", "dog")
    T.eq(t.get "lilx", "puppy")
  end)

  test("prefix yields all entries under the prefix", function()
    local t = trie.new()
    t.insert("lil", 1)
    t.insert("lilx", 2)
    t.insert("liy", 3)
    t.insert("spot", 4)

    T.eq(collect(t.prefix "li"), { lil = 1, lilx = 2, liy = 3 })
  end)

  test("prefix yields the prefix key itself if it has a value", function()
    local t = trie.new()
    t.insert("lil", 1)
    t.insert("lilx", 2)

    T.eq(collect(t.prefix "lil"), { lil = 1, lilx = 2 })
  end)

  test("prefix on empty string yields all entries", function()
    local t = trie.new()
    t.insert("lil", 1)
    t.insert("spot", 2)

    T.eq(collect(t.prefix ""), { lil = 1, spot = 2 })
  end)

  test("prefix on absent prefix yields nothing", function()
    local t = trie.new()
    t.insert("lil", 1)

    T.eq(collect(t.prefix "spot"), {})
  end)

  test("prefix on empty trie yields nothing", function()
    local t = trie.new()

    T.eq(collect(t.prefix ""), {})
  end)

  test("instances are independent", function()
    local a = trie.new()
    local b = trie.new()
    a.insert("lil", "a")
    b.insert("lil", "b")

    T.eq(a.get "lil", "a")
    T.eq(b.get "lil", "b")
  end)
end)
