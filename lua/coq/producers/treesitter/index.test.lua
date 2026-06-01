local T = require "coq.lib.test"
local index = require "coq.producers.treesitter.index"

---@param iter lib.Iterator<any>
---@return string[]
local texts = function(iter)
  local out = {}
  for item in
    iter --[[@as lib.Iterator<treesitter.Item>]]
  do
    table.insert(out, item.text)
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
    text = "labrador",
    kind = "variable",
    range = { 0, 0 },
  }, overrides or {}) --[[@as treesitter.Item]]
end

T.describe("treesitter.index", function(test)
  test("search routes by filetype, buf, and prefix", function()
    index.prune {}
    index.insert(mk { text = "labrador", buf = 1, filetype = "lua" })
    index.insert(mk { text = "lily", buf = 1, filetype = "lua" })
    index.insert(mk { text = "spot", buf = 2, filetype = "lua" })
    index.insert(mk { text = "labrador", buf = 3, filetype = "python" })

    T.eq(texts(index.search { filetype = "lua", buf = 1, keyword_before = "la" }), { "labrador" })
    T.eq(texts(index.search { filetype = "lua", buf = 2, keyword_before = "sp" }), { "spot" })
    T.eq(texts(index.search { filetype = "python", buf = 3, keyword_before = "la" }), { "labrador" })
  end)

  test("nil buf fans out across bufs within a filetype", function()
    index.prune {}
    index.insert(mk { text = "labrador", buf = 1, filetype = "lua" })
    index.insert(mk { text = "lily", buf = 2, filetype = "lua" })

    T.eq(texts(index.search { filetype = "lua", keyword_before = "l" }), { "labrador", "lily" })
  end)

  test("prune by buf removes only that buf", function()
    index.prune {}
    index.insert(mk { text = "labrador", buf = 1, filetype = "lua" })
    index.insert(mk { text = "lily", buf = 2, filetype = "lua" })

    index.prune { buf = 1 }

    T.eq(texts(index.search {}), { "lily" })
  end)

  test("inserting same text into the same buf overwrites", function()
    index.prune {}
    index.insert(mk { text = "labrador", buf = 1, filetype = "lua", kind = "variable" })
    index.insert(mk { text = "labrador", buf = 1, filetype = "lua", kind = "function" })

    local seen = {}
    for item in
      index.search { filetype = "lua", buf = 1, keyword_before = "lab" } --[[@as lib.Iterator<treesitter.Item>]]
    do
      table.insert(seen, item.kind)
    end
    T.eq(seen, { "function" })
  end)
end)
