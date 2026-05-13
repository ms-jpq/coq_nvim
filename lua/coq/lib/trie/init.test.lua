local T = require "coq.lib.test"
local trie = require "coq.lib.trie"

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
    t.insert("rex", "good")
    T.eq(t.get "rex", "good")
  end)

  test("get on missing key returns nil", function()
    local t = trie.new()
    t.insert("rex", "good")
    T.eq(t.get "spot", nil)
  end)

  test("get on internal node without value returns nil", function()
    local t = trie.new()
    t.insert("rex", "good")
    T.eq(t.get "re", nil)
  end)

  test("get on extension past a terminal returns nil", function()
    local t = trie.new()
    t.insert("rex", "good")
    T.eq(t.get "rexx", nil)
  end)

  test("insert overwrites previous value", function()
    local t = trie.new()
    t.insert("rex", "good")
    t.insert("rex", "bad")
    T.eq(t.get "rex", "bad")
  end)

  test("stores keys where one is a prefix of another", function()
    local t = trie.new()
    t.insert("rex", "dog")
    t.insert("rexx", "puppy")
    T.eq(t.get "rex", "dog")
    T.eq(t.get "rexx", "puppy")
  end)

  test("prefix yields all entries under the prefix", function()
    local t = trie.new()
    t.insert("rex", 1)
    t.insert("rexx", 2)
    t.insert("rey", 3)
    t.insert("spot", 4)
    T.eq(collect(t.prefix "re"), { rex = 1, rexx = 2, rey = 3 })
  end)

  test("prefix yields the prefix key itself if it has a value", function()
    local t = trie.new()
    t.insert("rex", 1)
    t.insert("rexx", 2)
    T.eq(collect(t.prefix "rex"), { rex = 1, rexx = 2 })
  end)

  test("prefix on empty string yields all entries", function()
    local t = trie.new()
    t.insert("rex", 1)
    t.insert("spot", 2)
    T.eq(collect(t.prefix ""), { rex = 1, spot = 2 })
  end)

  test("prefix on absent prefix yields nothing", function()
    local t = trie.new()
    t.insert("rex", 1)
    T.eq(collect(t.prefix "spot"), {})
  end)

  test("prefix on empty trie yields nothing", function()
    local t = trie.new()
    T.eq(collect(t.prefix ""), {})
  end)

  test("instances are independent", function()
    local a = trie.new()
    local b = trie.new()
    a.insert("rex", "a")
    b.insert("rex", "b")
    T.eq(a.get "rex", "a")
    T.eq(b.get "rex", "b")
  end)
end)
