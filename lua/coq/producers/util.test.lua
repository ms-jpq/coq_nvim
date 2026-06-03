local T = require "coq.lib.test"
local util = require "coq.producers.util"

---@param items table[]
---@return fun(): index.Hit<any>?
local from = function(items)
  local i = 0
  return function()
    i = i + 1
    local item = items[i]
    if item == nil then
      return nil
    end
    return { item = item, fuzzy = 0 }
  end
end

---@param iter lib.Iterator<table>
---@return table[]
local drain = function(iter)
  local out = {}
  for v in iter do
    table.insert(out, v)
  end
  return out
end

local settings = function(max)
  ---@diagnostic disable-next-line: missing-fields
  return { match = { max_results = max } } --[[@as config.Settings]]
end

local ctx = function(keyword_before)
  ---@diagnostic disable-next-line: missing-fields
  return { keyword_before = keyword_before or "" } --[[@as ctx.full]]
end

T.describe("producers.util.shape", function(test)
  test("dedups by word then caps", function()
    local out = drain(
      util.shape(settings(2), ctx(), from { { word = "spot" }, { word = "spot" }, { word = "fido" }, { word = "rex" } })
    )
    T.eq(#out, 2)
    T.eq(out[1].item.word, "spot")
    T.eq(out[2].item.word, "fido")
  end)

  test("dedup runs before take — duplicates don't burn budget", function()
    local out = drain(
      util.shape(
        settings(3),
        ctx(),
        from { { word = "spot" }, { word = "spot" }, { word = "spot" }, { word = "fido" }, { word = "rex" } }
      )
    )
    T.eq(
      vim.tbl_map(function(i)
        return i.item.word
      end, out),
      { "spot", "fido", "rex" }
    )
  end)

  test("yields all when source shorter than max", function()
    local out = drain(util.shape(settings(10), ctx(), from { { word = "spot" }, { word = "fido" } }))
    T.eq(#out, 2)
  end)

  test("max = 0 yields nothing", function()
    T.eq(drain(util.shape(settings(0), ctx(), from { { word = "spot" } })), {})
  end)

  test("items without a word field pass through (treesitter-style)", function()
    local out = drain(util.shape(settings(5), ctx(), from { { text = "spot" }, { text = "spot" }, { text = "fido" } }))
    T.eq(#out, 3)
  end)

  test("first occurrence wins; later duplicates dropped regardless of extra fields", function()
    local out = drain(util.shape(
      settings(5),
      ctx(),
      from {
        { word = "spot", breed = "labrador" },
        { word = "spot", breed = "retriever" },
        { word = "spot" },
      }
    ))
    T.eq(#out, 1)
    T.eq(out[1].item.breed, "labrador")
  end)

  test("drops items whose word equals the current keyword_before", function()
    local out =
      drain(util.shape(settings(5), ctx "lab", from { { word = "lab" }, { word = "labrador" }, { word = "lily" } }))
    T.eq(
      vim.tbl_map(function(i)
        return i.item.word
      end, out),
      { "labrador", "lily" }
    )
  end)
end)

T.describe("producers.util.item", function(test)
  local opts = { short_name = "BF", always_on_top = true }

  ---@param brackets string[]
  ---@return config.Settings
  local with = function(brackets)
    ---@diagnostic disable-next-line: missing-fields
    return { display = { pum = { source_context = brackets } } } --[[@as config.Settings]]
  end

  test("wraps short_name in the configured brackets", function()
    T.eq(util.item(with { "「", "」" }, opts, { word = "rex", kind = "Text", filter = "rex", fuzzy = 0 }).menu, "「BF」")
  end)

  test("threads empty brackets through unchanged", function()
    T.eq(
      util.item(with { "", "" }, { short_name = "TS" }, { word = "rex", kind = "Text", filter = "rex", fuzzy = 0 }).menu,
      "TS"
    )
  end)

  test("packs the canonical fields", function()
    local item = util.item(with { "「", "」" }, opts, { word = "rex", kind = "Text", filter = "rex", fuzzy = 0 })
    T.eq(item.word, "rex")
    T.eq(item.kind, "Text")
    T.eq(item.menu, "「BF」")
    T.eq(item.meta.filter, "rex")
    T.eq(item.meta.source, "BF")
    T.eq(item.meta.always_on_top, true)
    T.eq(type(item.meta["uid"]), "string")
    T.eq(#item.meta["uid"], 16)
  end)

  test("every call mints a fresh uid", function()
    local s = with { "", "" }
    local a = util.item(s, opts, { word = "spot", kind = "Text", filter = "spot", fuzzy = 0 })
    local b = util.item(s, opts, { word = "spot", kind = "Text", filter = "spot", fuzzy = 0 })
    T.eq(a.meta["uid"] ~= b.meta["uid"], true)
  end)

  test("forwards doc and snippet when present", function()
    local doc = { lines = { "good dog" }, filetype = "markdown" }
    local item = util.item(with { "", "" }, opts, {
      word = "fido",
      kind = "Snippet",
      filter = "fido",
      fuzzy = 0,
      doc = doc,
      snippet = "fido()$0",
    })
    T.eq(item.meta.doc, doc)
    T.eq(item.meta.snippet, "fido()$0")
  end)

  test("optional fields stay nil when omitted", function()
    local item = util.item(with { "", "" }, { short_name = "TX" }, { word = "lab", kind = "Text", filter = "lab", fuzzy = 0 })
    T.eq(item.meta.always_on_top, nil)
    T.eq(item.meta.doc, nil)
    T.eq(item.meta.snippet, nil)
  end)
end)

T.describe("producers.util.word_search", function(test)
  local ws_settings = function(exact)
    ---@diagnostic disable-next-line: missing-fields
    return { match = { exact_matches = exact or 2 } } --[[@as config.Settings]]
  end

  local seed = function(words)
    local s = util.word_search(ws_settings())()
    for _, w in pairs(words) do
      s.insert { word = w }
    end
    return s
  end

  ---@param iter lib.Iterator<table>
  local words = function(iter)
    local out = {}
    for v in iter do
      table.insert(out, v.item.word)
    end
    table.sort(out)
    return out
  end

  test("prefix matches the keyword", function()
    local s = seed { "labrador", "labradoodle", "lily", "rex" }
    T.eq(words(s.search { keyword_before = "lab" }), { "labradoodle", "labrador" })
  end)

  test("empty keyword yields everything (search.prune semantics)", function()
    local s = seed { "spot", "fido" }
    T.eq(words(s.search { keyword_before = "" }), { "fido", "spot" })
  end)

  test("nil keyword also yields everything — prune path uses this", function()
    local s = seed { "spot", "fido" }
    T.eq(words(s.search { keyword_before = nil }), { "fido", "spot" })
  end)

  test("below exact_matches threshold falls back to fuzzy child", function()
    local s = seed { "labrador" }
    -- "la" is 2 chars (= prefix); "l" is below, should still match via fuzzy
    T.eq(words(s.search { keyword_before = "l" }), { "labrador" })
  end)

  test("prune by word removes a single entry", function()
    local s = seed { "spot", "fido" }
    s.prune { keyword_before = "spot" }
    T.eq(words(s.search { keyword_before = "" }), { "fido" })
  end)
end)
