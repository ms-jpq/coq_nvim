local T = require "coq.lib.test"
local config = require "coq.config"
local index_m = require "coq.producers.registers.index"

local settings = config.merged()

---@param iter lib.Iterator<any>
---@return string[]
local words = function(iter)
  local out = {}
  for item in
    iter --[[@as lib.Iterator<registers.Item>]]
  do
    table.insert(out, item.word)
  end
  table.sort(out)
  return out
end

T.describe("registers.index", function(test)
  test("search routes by prefix across all registers", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", register = "0", linewise = false }
    index.insert { word = "lily", register = "0", linewise = false }
    index.insert { word = "spot", register = "+", linewise = false }

    T.eq(words(index.search { keyword_before = "la" }), { "labrador" })
    T.eq(words(index.search { keyword_before = "l" }), { "labrador", "lily" })
    T.eq(words(index.search { keyword_before = "sp" }), { "spot" })
  end)

  test("nil keyword_before fans across all words", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", register = "0", linewise = false }
    index.insert { word = "spot", register = "+", linewise = false }

    T.eq(words(index.search {}), { "labrador", "spot" })
  end)

  test("prune nukes everything across registers", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", register = "0", linewise = false }
    index.insert { word = "spot", register = "+", linewise = false }

    index.prune {}

    T.eq(words(index.search {}), {})
  end)

  test("linewise items round-trip line text via item.line", function()
    local index = index_m.new(settings)
    index.insert { word = "spot", register = "0", linewise = true, line = "spot is a good dog" }

    local out = {}
    for item in index.search { keyword_before = "sp" } do
      table.insert(out, item.line)
    end
    T.eq(out, { "spot is a good dog" })
  end)
end)
