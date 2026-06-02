local T = require "coq.lib.test"
local config = require "coq.config"
local index_m = require "coq.producers.buffers.index"

local settings = config.merged()

---@param iter lib.Iterator<any>
---@return string[]
local words = function(iter)
  local out = {}
  for item in
    iter --[[@as lib.Iterator<buffer.Item>]]
  do
    table.insert(out, item.word)
  end
  table.sort(out)
  return out
end

T.describe("buffer.index", function(test)
  test("search routes by filetype, buf, and prefix", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "spot", buf = 2, filetype = "lua", filename = "" }
    index.insert { word = "labrador", buf = 3, filetype = "python", filename = "" }

    T.eq(words(index.search { filetype = "lua", buf = 1, keyword_before = "la" }), { "labrador" })
    T.eq(words(index.search { filetype = "lua", buf = 1, keyword_before = "li" }), { "lily" })
    T.eq(words(index.search { filetype = "lua", buf = 2, keyword_before = "sp" }), { "spot" })
    T.eq(words(index.search { filetype = "python", buf = 3, keyword_before = "la" }), { "labrador" })
  end)

  test("nil filetype fans out across filetypes", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "labradoodle", buf = 2, filetype = "python", filename = "" }

    T.eq(words(index.search { keyword_before = "lab" }), { "labradoodle", "labrador" })
  end)

  test("nil buf fans out across bufs within a filetype", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 2, filetype = "lua", filename = "" }
    index.insert { word = "spot", buf = 3, filetype = "python", filename = "" }

    T.eq(words(index.search { filetype = "lua", keyword_before = "l" }), { "labrador", "lily" })
  end)

  test("prune by buf removes only that buf within a filetype", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "" }
    index.insert { word = "lily", buf = 2, filetype = "lua", filename = "" }

    index.prune { filetype = "lua", buf = 1 }

    T.eq(words(index.search { filetype = "lua" }), { "lily" })
  end)

  test("inserting same word into the same buf overwrites", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "old.lua" }
    index.insert { word = "labrador", buf = 1, filetype = "lua", filename = "new.lua" }

    local seen = {}
    for item in index.search { filetype = "lua", buf = 1, keyword_before = "lab" } do
      table.insert(seen, item.filename)
    end
    T.eq(seen, { "new.lua" })
  end)
end)
