local T = require "coq.lib.test"
local trie = require "coq.lib.index.trie"

local spec = {
  insert_key = function(item)
    return item.word
  end,
  query_key = function(ctx)
    return ctx.prefix
  end,
  prefix = math.huge,
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
  test("search yields every item whose key starts with the prefix", function()
    local t = trie.new(spec)
    t.insert { word = "lil" }
    t.insert { word = "lilx" }
    t.insert { word = "liy" }
    t.insert { word = "spot" }

    T.eq(collect(t.search { prefix = "li" }), { "lil", "lilx", "liy" })
  end)

  test("buckets by the first two chars: a longer prefix yields the whole bucket", function()
    local t = trie.new(vim.tbl_extend("force", spec, { prefix = 2 }))
    t.insert { word = "labrador" }
    t.insert { word = "lazy" } -- same "la" bucket, diverges at char 3
    t.insert { word = "lily" } -- "li" bucket

    -- a query past two chars does not narrow within the bucket (fuzzy)
    T.eq(collect(t.search { prefix = "labr" }), { "labrador", "lazy" })
    T.eq(collect(t.search { prefix = "la" }), { "labrador", "lazy" })
    -- a single char fans across every two-char bucket beneath it
    T.eq(collect(t.search { prefix = "l" }), { "labrador", "lazy", "lily" })
  end)

  test("prefix length is configurable at construction", function()
    local one = trie.new(vim.tbl_extend("force", spec, { prefix = 1 }))
    one.insert { word = "labrador" }
    one.insert { word = "lily" }
    one.insert { word = "spot" }

    -- prefix = 1: a single "l" bucket holds both l-words
    T.eq(collect(one.search { prefix = "lab" }), { "labrador", "lily" })
    T.eq(collect(one.search { prefix = "s" }), { "spot" })

    local three = trie.new(vim.tbl_extend("force", spec, { prefix = 3 }))
    three.insert { word = "labrador" }
    three.insert { word = "label" } -- shares "lab"
    three.insert { word = "lazy" } -- "laz", a distinct bucket at depth 3

    T.eq(collect(three.search { prefix = "labrador" }), { "label", "labrador" })
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

    local from_a = assert(a.search { prefix = "lil" }())
    local from_b = assert(b.search { prefix = "lil" }())
    T.eq(from_a.which, "a")
    T.eq(from_b.which, "b")
  end)
end)
