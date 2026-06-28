local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local bundled = require "coq.producers.snippets.loaders.bundled"

---@param filetype string
---@return snippets.Source
local src_of = function(filetype)
  return { path = "/tmp/coq+snippets+v3/" .. filetype .. ".json", mtime = 0, filetype = filetype }
end

local parents_set = TH.set_of

---@param t table
---@return string
local enc = function(t)
  return vim.json.encode(t)
end

T.describe({ "bundled.parse :: malformed" }, function(test)
  test({ "not JSON → err" }, function()
    local err = bundled.parse(src_of "lua", "{ not json")
    assert(err and string.find(err, "malformed", 1, true), "expected malformed err")
  end)

  test({ "JSON without snippets array → err" }, function()
    local err = bundled.parse(src_of "lua", enc { extends = {} })
    assert(err and string.find(err, "malformed", 1, true), "expected malformed err")
  end)

  test({ "snippets is not a table → err" }, function()
    local err = bundled.parse(src_of "lua", enc { snippets = "nope" })
    assert(err and string.find(err, "malformed", 1, true), "expected malformed err")
  end)
end)

T.describe({ "bundled.parse :: extends" }, function(test)
  test({ "extends array collected and lowercased" }, function()
    local _, parents, _ = bundled.parse(src_of "lua", enc { extends = { "C", "Cpp" }, snippets = {} })
    T.eq(parents_set(parents), { c = true, cpp = true })
  end)

  test({ "missing extends → no parents" }, function()
    local _, parents, _ = bundled.parse(src_of "lua", enc { snippets = {} })
    T.eq(parents, {})
  end)

  test({ "non-string entries in extends are skipped" }, function()
    local _, parents, _ = bundled.parse(src_of "lua", enc { extends = { "c", 42, "" }, snippets = {} })
    T.eq(parents_set(parents), { c = true })
  end)
end)

T.describe({ "bundled.parse :: per-ft bundle" }, function(test)
  test({ "all snippet entries belong to src.filetype" }, function()
    local _, _, sourced =
      bundled.parse(src_of "lua", enc { snippets = { { matches = { foo = true }, content = "A" } } })
    T.eq(#sourced.snippets, 1)
    T.eq(sourced.snippets[1].filetype, "lua")
    T.eq(sourced.snippets[1].word, "foo")
    T.eq(sourced.snippets[1].body, "A")
  end)

  test({ "one entry with N matches → N items sharing body" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc {
        snippets = { { matches = { foo = true, bar = true }, content = "shared" } },
      }
    )
    T.eq(#sourced.snippets, 2)
    for _, s in ipairs(sourced.snippets) do
      T.eq(s.body, "shared")
    end
  end)
end)

T.describe({ "bundled.parse :: field handling" }, function(test)
  test({ "label and doc preserved when strings" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { matches = { foo = true }, content = "A", label = "L", doc = "D" } } }
    )
    T.eq(sourced.snippets[1].label, "L")
    T.eq(sourced.snippets[1].doc, "D")
  end)

  test({ "missing optional fields default to empty string" }, function()
    local _, _, sourced = bundled.parse(src_of "lua", enc { snippets = { { matches = { foo = true } } } })
    T.eq(sourced.snippets[1].body, "")
    T.eq(sourced.snippets[1].label, "")
    T.eq(sourced.snippets[1].doc, "")
  end)
end)
