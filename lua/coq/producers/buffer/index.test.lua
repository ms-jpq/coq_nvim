---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local index = require "coq.producers.buffer.index"

---@param iter index.SearchIter
---@return string[]
local words = function(iter)
  local out = {}
  for item in
    iter --[[@as fun(): buffer.Item?]]
  do
    table.insert(out, item.word)
  end
  table.sort(out)
  return out
end

T.describe("buffer.index", function(test)
  test("search routes by filetype, buf, and prefix", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "spot", buf = 2, filetype = "lua", filename = "" }
    index.insert { word = "labrador", buf = 3, filetype = "python", filename = "" }

    T.eq(words(index.search { filetype = "lua", buf = 1, line_before = "la" }), { "labrador" })
    T.eq(words(index.search { filetype = "lua", buf = 1, line_before = "li" }), { "lily" })
    T.eq(words(index.search { filetype = "lua", buf = 2, line_before = "sp" }), { "spot" })
    T.eq(words(index.search { filetype = "python", buf = 3, line_before = "la" }), { "labrador" })
  end)

  test("nil filetype fans out across filetypes", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "labradoodle", buf = 2, filetype = "python", filename = "" }

    T.eq(words(index.search { line_before = "lab" }), { "labradoodle", "labrador" })
  end)

  test("nil buf fans out across bufs within a filetype", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 2, filetype = "lua", filename = "" }
    index.insert { word = "spot", buf = 3, filetype = "python", filename = "" }

    T.eq(words(index.search { filetype = "lua", line_before = "l" }), { "labrador", "lily" })
  end)

  test("nil line_before fans across every word", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "spot", buf = 1, filetype = "lua", filename = "" }

    T.eq(words(index.search { filetype = "lua", buf = 1 }), { "labrador", "lily", "spot" })
  end)

  test("line_before extracts the trailing word for the prefix", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }

    T.eq(words(index.search { filetype = "lua", buf = 1, line_before = "hello la" }), { "labrador" })
    T.eq(words(index.search { filetype = "lua", buf = 1, line_before = "no_match xy" }), {})
  end)

  test("prune by buf removes only that buf within a filetype", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 2, filetype = "lua", filename = "" }

    index.prune { filetype = "lua", buf = 1 }

    T.eq(words(index.search { filetype = "lua" }), { "lily" })
  end)

  test("inserting same word into the same buf overwrites", function()
    index.prune {}
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "old.lua" }
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "new.lua" }

    local seen = {}
    for item in
      index.search { filetype = "lua", buf = 1, line_before = "lab" } --[[@as fun(): buffer.Item?]]
    do
      table.insert(seen, item.filename)
    end
    T.eq(seen, { "new.lua" })
  end)
end)
