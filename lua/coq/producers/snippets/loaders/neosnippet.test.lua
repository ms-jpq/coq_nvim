local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local neosnippet = require "coq.producers.snippets.loaders.neosnippet"

---@param filetype string
---@return snippets.Source
local src_of = function(filetype)
  return { kind = "neosnippet", path = "/tmp/" .. filetype .. ".snippets", mtime = 0, filetype = filetype }
end

local parents_set = TH.set_of

T.describe({ "neosnippet.parse :: basics" }, function(test)
  test({ "empty input → no err, no items" }, function()
    local err, parents, sourced = neosnippet.parse(src_of "lua", "")
    T.eq(err, nil)
    T.eq(parents, {})
    T.eq(#sourced.snippets, 0)
  end)

  test({ "single snippet with body" }, function()
    local err, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo",
      "\tprint('dog')",
    }, "\n"))
    T.eq(err, nil)
    T.eq(#sourced.snippets, 1)
    T.eq(sourced.snippets[1].word, "foo")
    T.eq(sourced.snippets[1].body, "print('dog')")
    T.eq(sourced.snippets[1].filetype, "lua")
    T.eq(sourced.snippets[1].grammar, "lsp")
  end)

  test({ "header label after name" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo Good Boy",
      "\tprint('dog')",
    }, "\n"))
    T.eq(sourced.snippets[1].label, "Good Boy")
  end)

  test({ "header label in quotes is unwrapped" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      'snippet foo "Good Boy"',
      "\tprint('dog')",
    }, "\n"))
    T.eq(sourced.snippets[1].label, "Good Boy")
  end)

  test({ "abbr line overrides header label" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo header label",
      "abbr Real Label",
      "\tprint('dog')",
    }, "\n"))
    T.eq(sourced.snippets[1].label, "Real Label")
  end)
end)

T.describe({ "neosnippet.parse :: aliases" }, function(test)
  test({ "alias adds extra words sharing the same body" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo",
      "alias bar",
      "alias baz",
      "\tprint('dog')",
    }, "\n"))
    local words = {}
    for _, s in ipairs(sourced.snippets) do
      words[s.word] = s.body
    end
    T.eq(words.foo, "print('dog')")
    T.eq(words.bar, "print('dog')")
    T.eq(words.baz, "print('dog')")
  end)

  test({ "duplicate alias dedupes" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo",
      "alias foo",
      "\tprint('dog')",
    }, "\n"))
    T.eq(#sourced.snippets, 1)
  end)
end)

T.describe({ "neosnippet.parse :: directives" }, function(test)
  test({ "extends collects parent filetypes" }, function()
    local _, parents, _ = neosnippet.parse(src_of "lua", "extends c, cpp")
    T.eq(parents_set(parents), { c = true, cpp = true })
  end)

  test({ "extends lowercases and strips whitespace" }, function()
    local _, parents, _ = neosnippet.parse(src_of "lua", "extends   C  ,   CPP  ")
    T.eq(parents_set(parents), { c = true, cpp = true })
  end)

  test({ "include takes the file stem" }, function()
    local _, parents, _ = neosnippet.parse(src_of "lua", "include other.snippets")
    T.eq(parents_set(parents), { other = true })
  end)

  test({ "comments are skipped" }, function()
    local err, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "# a comment about dogs",
      "snippet foo",
      "\tbody",
    }, "\n"))
    T.eq(err, nil)
    T.eq(#sourced.snippets, 1)
  end)

  test({ "ignored starts pass without error" }, function()
    for _, start in ipairs { "delete", "options", "regexp", "source" } do
      local err = neosnippet.parse(src_of "lua", start .. " whatever")
      T.eq(err, nil)
    end
  end)
end)

T.describe({ "neosnippet.parse :: body handling" }, function(test)
  test({ "blank lines inside body preserved" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo",
      "\tline1",
      "",
      "\tline3",
    }, "\n"))
    T.eq(sourced.snippets[1].body, "line1\n\nline3")
  end)

  test({ "common indentation dedented" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo",
      "\t\tdeeper",
      "\t\talso_deeper",
    }, "\n"))
    T.eq(sourced.snippets[1].body, "deeper\nalso_deeper")
  end)

  test({ "two snippets parsed independently" }, function()
    local _, _, sourced = neosnippet.parse(src_of "lua", table.concat({
      "snippet foo",
      "\tA",
      "snippet bar",
      "\tB",
    }, "\n"))
    T.eq(#sourced.snippets, 2)
    local map = {}
    for _, s in ipairs(sourced.snippets) do
      map[s.word] = s.body
    end
    T.eq(map.foo, "A")
    T.eq(map.bar, "B")
  end)
end)

T.describe({ "neosnippet.parse :: errors" }, function(test)
  test({ "body line before any snippet header → err" }, function()
    local err = neosnippet.parse(src_of "lua", "\torphan body")
    assert(err and string.find(err, "Expected snippet name", 1, true), "expected name err, got " .. tostring(err))
  end)

  test({ "unknown line start → err" }, function()
    local err = neosnippet.parse(src_of "lua", "snipet foo")
    assert(err and string.find(err, "Unexpected line start", 1, true), "expected unexpected-start err")
  end)
end)
