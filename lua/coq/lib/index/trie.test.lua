---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local trie = require "coq.lib.index.trie"

local spec = {
  insert_key = function(item)
    return item.word
  end,
  query_key = function(ctx)
    return ctx.prefix
  end,
}

local collect = function(iter)
  local out = {}
  for item in iter do
    table.insert(out, item.word)
  end
  table.sort(out)
  return out
end

T.describe("trie", function(test)
  test("search with exact key yields the item inserted at that key", function()
    local t = trie.new(spec)
    t.insert { word = "lil", kind = "dog" }

    T.eq(collect(t.search { prefix = "lil" }), { "lil" })
  end)

  test("search yields every item whose key starts with the prefix", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }
    t.insert { word = "lilx" }
    t.insert { word = "liy" }
    t.insert { word = "spot" }

    T.eq(collect(t.search { prefix = "li" }), { "lil", "lilx", "liy" })
  end)

  test("search includes the prefix key itself when it has an item", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }
    t.insert { word = "lilx" }

    T.eq(collect(t.search { prefix = "lil" }), { "lil", "lilx" })
  end)

  test("search on nil prefix yields every item", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }
    t.insert { word = "spot" }

    T.eq(collect(t.search {}), { "lil", "spot" })
  end)

  test("search on absent prefix yields nothing", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }

    T.eq(collect(t.search { prefix = "spot" }), {})
  end)

  test("insert with the same key overwrites the previous item", function()
    local t = trie.new(spec)
    t.insert { word = "lil", buf = 1 }
    t.insert { word = "lil", buf = 2 }

    local seen = {}
    for item in t.search { prefix = "lil" } do
      table.insert(seen, item.buf)
    end
    T.eq(seen, { 2 })
  end)

  test("prune removes every item under the prefix", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }
    t.insert { word = "lilx" }
    t.insert { word = "liy" }
    t.insert { word = "spot" }

    t.prune { prefix = "li" }

    T.eq(collect(t.search {}), { "spot" })
  end)

  test("prune on absent prefix is a no-op", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }

    t.prune { prefix = "spot" }

    T.eq(collect(t.search {}), { "lil" })
  end)

  test("prune with nil key wipes the trie", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }
    t.insert { word = "spot" }

    t.prune {}

    T.eq(collect(t.search {}), {})
  end)

  test("instances are independent", function()
    local a, b = trie.new(spec), trie.new(spec)
    a.insert { word = "lil", which = "a" }
    b.insert { word = "lil", which = "b" }

    local from_a = a.search { prefix = "lil" }()
    local from_b = b.search { prefix = "lil" }()
    T.eq(from_a.which, "a")
    T.eq(from_b.which, "b")
  end)
end)
