local T = require "coq.lib.test"
local config = require "coq.config"
local index_m = require "coq.producers.tree_sitter.index"

local settings = config.merged()

---@param iter fun(): index.Hit<treesitter.Item>?
---@return string[]
local words = function(iter)
  local out = {}
  for hit in iter do
    table.insert(out, hit.item.word)
  end
  table.sort(out)
  return out
end

---@param overrides? table
---@return treesitter.Item
local mk = function(overrides)
  return vim.tbl_extend("force", {
    buf = 1,
    filetype = "lua",
    filename = "",
    word = "labrador",
    kind = "variable",
    range = { 0, 0 },
  }, overrides or {}) --[[@as treesitter.Item]]
end

T.describe({ "treesitter.index" }, function(test)
  test({ "search routes by filetype, buf, and prefix" }, function()
    local index = index_m.new(settings)
    index.insert(mk { word = "labrador", buf = 1, filetype = "lua" })
    index.insert(mk { word = "lily", buf = 1, filetype = "lua" })
    index.insert(mk { word = "spot", buf = 2, filetype = "lua" })
    index.insert(mk { word = "labrador", buf = 3, filetype = "python" })

    T.eq(words(index.search { filetype = "lua", buf = 1, keyword_before = "la" }), { "labrador" })
    T.eq(words(index.search { filetype = "lua", buf = 2, keyword_before = "sp" }), { "spot" })
    T.eq(words(index.search { filetype = "python", buf = 3, keyword_before = "la" }), { "labrador" })
  end)

  test({ "nil buf fans out across bufs within a filetype" }, function()
    local index = index_m.new(settings)
    index.insert(mk { word = "labrador", buf = 1, filetype = "lua" })
    index.insert(mk { word = "lily", buf = 2, filetype = "lua" })

    T.eq(words(index.search { filetype = "lua", keyword_before = "l" }), { "labrador", "lily" })
  end)

  test({ "prune by buf removes only that buf" }, function()
    local index = index_m.new(settings)
    index.insert(mk { word = "labrador", buf = 1, filetype = "lua" })
    index.insert(mk { word = "lily", buf = 2, filetype = "lua" })

    index.prune { buf = 1 }

    T.eq(words(index.search {}), { "lily" })
  end)

  test({ "inserting same text into the same buf overwrites" }, function()
    local index = index_m.new(settings)
    index.insert(mk { word = "labrador", buf = 1, filetype = "lua", kind = "variable" })
    index.insert(mk { word = "labrador", buf = 1, filetype = "lua", kind = "function" })

    local seen = {}
    for hit in index.search { filetype = "lua", buf = 1, keyword_before = "lab" } do
      table.insert(seen, hit.item.kind)
    end
    T.eq(seen, { "function" })
  end)
end)
