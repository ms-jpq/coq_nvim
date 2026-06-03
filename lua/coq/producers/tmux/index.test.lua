local T = require "coq.lib.test"
local config = require "coq.config"
local index_m = require "coq.producers.tmux.index"

local settings = config.merged()

---@param iter lib.Iterator<tmux.Item>
---@return string[]
local words = function(iter)
  local out = {}
  for item in iter do
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
    local index = index_m.new(settings)
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "lily", pane = "p1", meta = mk_meta() }
    index.insert { word = "spot", pane = "p2", meta = mk_meta() }

    T.eq(words(index.search { pane = "p1", keyword_before = "la" }), { "labrador" })
    T.eq(words(index.search { pane = "p1", keyword_before = "l" }), { "labrador", "lily" })
    T.eq(words(index.search { pane = "p2", keyword_before = "sp" }), { "spot" })
  end)

  test("nil pane fans out across panes", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "labradoodle", pane = "p2", meta = mk_meta() }

    T.eq(words(index.search { keyword_before = "lab" }), { "labradoodle", "labrador" })
  end)

  test("prune by pane removes only that pane", function()
    local index = index_m.new(settings)
    index.insert { word = "labrador", pane = "p1", meta = mk_meta() }
    index.insert { word = "spot", pane = "p2", meta = mk_meta() }

    index.prune { pane = "p1" }

    T.eq(words(index.search {}), { "spot" })
  end)

  test("inserting same word into the same pane overwrites", function()
    local index = index_m.new(settings)
    local first = mk_meta { session_name = "a", window_index = "", window_name = "", pane_index = "", pane_title = "" }
    local second = mk_meta { session_name = "b", window_index = "", window_name = "", pane_index = "", pane_title = "" }
    index.insert { word = "labrador", pane = "p1", meta = first }
    index.insert { word = "labrador", pane = "p1", meta = second }

    local seen = {}
    for item in index.search { pane = "p1", keyword_before = "lab" } do
      table.insert(seen, item.meta.session_name)
    end
    T.eq(seen, { "b" })
  end)
end)
