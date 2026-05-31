---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local index = require "coq.producers.tmux.index"

---@param iter index.SearchIter
---@return string[]
local words = function(iter)
  local out = {}
  for item in
    iter --[[@as fun(): tmux.Item?]]
  do
    table.insert(out, item.word)
  end
  table.sort(out)
  return out
end

---@param meta? tmux.PaneMeta
---@return tmux.PaneMeta
local mk_meta = function(meta)
  return meta
    or {
      session_name = "",
      window_index = "",
      window_name = "",
      pane_index = "",
      pane_title = "",
    }
end

T.describe("tmux.index", function(test)
  test("search routes by pane and prefix", function()
    index.prune {}
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "lily", pane = "p1", meta = mk_meta() }
    index.insert { word = "spot", pane = "p2", meta = mk_meta() }

    T.eq(words(index.search { pane = "p1", line_before = "la" }), { "labrador" })
    T.eq(words(index.search { pane = "p1", line_before = "l" }), { "labrador", "lily" })
    T.eq(words(index.search { pane = "p2", line_before = "sp" }), { "spot" })
  end)

  test("nil pane fans out across panes", function()
    index.prune {}
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "labradoodle", pane = "p2", meta = mk_meta() }

    T.eq(words(index.search { line_before = "lab" }), { "labradoodle", "labrador" })
  end)

  test("nil line_before fans across every word in the pane", function()
    index.prune {}
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "lily", pane = "p1", meta = mk_meta() }

    T.eq(words(index.search { pane = "p1" }), { "labrador", "lily" })
  end)

  test("line_before extracts the trailing word for the prefix", function()
    index.prune {}
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }

    T.eq(words(index.search { pane = "p1", line_before = "hello la" }), { "labrador" })
    T.eq(words(index.search { pane = "p1", line_before = "xy" }), {})
  end)

  test("prune by pane removes only that pane", function()
    index.prune {}
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "spot", pane = "p2", meta = mk_meta() }

    index.prune { pane = "p1" }

    T.eq(words(index.search {}), { "spot" })
  end)

  test("inserting same word into the same pane overwrites", function()
    index.prune {}
    local first = mk_meta { session_name = "a", window_index = "", window_name = "", pane_index = "", pane_title = "" }
    local second = mk_meta { session_name = "b", window_index = "", window_name = "", pane_index = "", pane_title = "" }
    index.insert { word = "labrador", pane = "p1", meta = first }
    index.insert { word = "labrador", pane = "p1", meta = second }

    local seen = {}
    for item in
      index.search { pane = "p1", line_before = "lab" } --[[@as fun(): tmux.Item?]]
    do
      table.insert(seen, item.meta.session_name)
    end
    T.eq(seen, { "b" })
  end)
end)
