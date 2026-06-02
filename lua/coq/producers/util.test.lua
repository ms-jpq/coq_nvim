local T = require "coq.lib.test"
local util = require "coq.producers.util"

---@param items table[]
---@return lib.Iterator<table>
local from = function(items)
  local i = 0
  return function()
    i = i + 1
    return items[i]
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
    T.eq(out[1].word, "spot")
    T.eq(out[2].word, "fido")
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
        return i.word
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
    T.eq(out[1].breed, "labrador")
  end)

  test("drops items whose word equals the current keyword_before", function()
    local out =
      drain(util.shape(settings(5), ctx "lab", from { { word = "lab" }, { word = "labrador" }, { word = "lily" } }))
    T.eq(
      vim.tbl_map(function(i)
        return i.word
      end, out),
      { "labrador", "lily" }
    )
  end)
end)

T.describe("producers.util.menu", function(test)
  ---@param brackets string[]
  ---@return config.Settings
  local with = function(brackets)
    ---@diagnostic disable-next-line: missing-fields
    return { display = { pum = { source_context = brackets } } } --[[@as config.Settings]]
  end

  test("wraps short_name in the configured brackets", function()
    T.eq(util.menu(with { "「", "」" }, { short_name = "BF" }), "「BF」")
  end)

  test("threads empty brackets through unchanged", function()
    T.eq(util.menu(with { "", "" }, { short_name = "TS" }), "TS")
  end)
end)

T.describe("producers.util.item", function(test)
  local opts = { short_name = "BF", always_on_top = true }

  test("packs the seven canonical fields", function()
    local item = util.item(opts, { word = "rex", kind = "Text", menu = "「BF」", filter = "rex" })
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
    local a = util.item(opts, { word = "spot", kind = "Text", menu = "」" })
    local b = util.item(opts, { word = "spot", kind = "Text", menu = "」" })
    T.eq(a.meta["uid"] ~= b.meta["uid"], true)
  end)

  test("forwards doc and snippet when present", function()
    local doc = { lines = { "good dog" }, filetype = "markdown" }
    local item = util.item(opts, {
      word = "fido",
      kind = "Snippet",
      menu = "」",
      doc = doc,
      snippet = "fido()$0",
    })
    T.eq(item.meta.doc, doc)
    T.eq(item.meta.snippet, "fido()$0")
  end)

  test("optional fields stay nil when omitted", function()
    local item = util.item({ short_name = "TX" }, { word = "lab", kind = "Text", menu = "」" })
    T.eq(item.meta.always_on_top, nil)
    T.eq(item.meta.filter, nil)
    T.eq(item.meta.doc, nil)
    T.eq(item.meta.snippet, nil)
  end)
end)
