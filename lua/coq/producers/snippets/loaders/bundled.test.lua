local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local bundled = require "coq.producers.snippets.loaders.bundled"

---@param filetype string
---@return snippets.Source
local src_of = function(filetype)
  return { kind = "bundle", path = "/tmp/coq+snippets+v2.json", mtime = 0, filetype = filetype }
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
    local _, parents, _ = bundled.parse(
      src_of "lua",
      enc { extends = { "C", "Cpp" }, snippets = {} }
    )
    T.eq(parents_set(parents), { c = true, cpp = true })
  end)

  test({ "missing extends → no parents" }, function()
    local _, parents, _ = bundled.parse(src_of "lua", enc { snippets = {} })
    T.eq(parents, {})
  end)

  test({ "non-string entries in extends are skipped" }, function()
    local _, parents, _ = bundled.parse(
      src_of "lua",
      enc { extends = { "c", 42, "" }, snippets = {} }
    )
    T.eq(parents_set(parents), { c = true })
  end)
end)

T.describe({ "bundled.parse :: snippet filtering" }, function(test)
  test({ "only emits snippets matching src.filetype" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc {
        snippets = {
          { filetype = "lua",    matches = { foo = true }, content = "A" },
          { filetype = "python", matches = { bar = true }, content = "B" },
        },
      }
    )
    T.eq(#sourced.snippets, 1)
    T.eq(sourced.snippets[1].word, "foo")
    T.eq(sourced.snippets[1].body, "A")
  end)

  test({ "filetype is case-folded against src" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { filetype = "LUA", matches = { foo = true }, content = "A" } } }
    )
    T.eq(#sourced.snippets, 1)
  end)

  test({ "one entry with N matches → N items sharing body" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc {
        snippets = {
          { filetype = "lua", matches = { foo = true, bar = true }, content = "shared" },
        },
      }
    )
    T.eq(#sourced.snippets, 2)
    for _, s in ipairs(sourced.snippets) do
      T.eq(s.body, "shared")
    end
  end)
end)

T.describe({ "bundled.parse :: field handling" }, function(test)
  test({ "grammar 'lit' kept" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { filetype = "lua", matches = { foo = true }, content = "A", grammar = "lit" } } }
    )
    T.eq(sourced.snippets[1].grammar, "lit")
  end)

  test({ "grammar 'snu' kept" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { filetype = "lua", matches = { foo = true }, content = "A", grammar = "snu" } } }
    )
    T.eq(sourced.snippets[1].grammar, "snu")
  end)

  test({ "unknown grammar falls back to lsp" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { filetype = "lua", matches = { foo = true }, content = "A", grammar = "exotic" } } }
    )
    T.eq(sourced.snippets[1].grammar, "lsp")
  end)

  test({ "label and doc preserved when strings" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc {
        snippets = {
          { filetype = "lua", matches = { foo = true }, content = "A", label = "L", doc = "D" },
        },
      }
    )
    T.eq(sourced.snippets[1].label, "L")
    T.eq(sourced.snippets[1].doc, "D")
  end)

  test({ "missing optional fields default to empty string" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { filetype = "lua", matches = { foo = true } } } }
    )
    T.eq(sourced.snippets[1].body, "")
    T.eq(sourced.snippets[1].label, "")
    T.eq(sourced.snippets[1].doc, "")
  end)

  test({ "entries missing filetype skipped" }, function()
    local _, _, sourced = bundled.parse(
      src_of "lua",
      enc { snippets = { { matches = { foo = true }, content = "A" } } }
    )
    T.eq(#sourced.snippets, 0)
  end)
end)
