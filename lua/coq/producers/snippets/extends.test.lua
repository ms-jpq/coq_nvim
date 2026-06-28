local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local extends_m = require "coq.producers.snippets.extends"

local set = TH.set_of

T.describe({ "snippets.extends.denormalize" }, function(test)
  test({ "empty input → empty result" }, function()
    T.eq(extends_m.denormalize(9, {}), {})
  end)

  test({ "each filetype includes itself" }, function()
    -- A → B; identity reflex means A is in its own closure too.
    local r = extends_m.denormalize(9, { { A = set { "B" } } })
    T.eq(r.A, set { "A", "B" })
  end)

  test({ "transitive — A→B→C produces A's closure {A,B,C}" }, function()
    local r = extends_m.denormalize(9, {
      { A = set { "B" }, B = set { "C" } },
    })
    T.eq(r.A, set { "A", "B", "C" })
    T.eq(r.B, set { "B", "C" })
  end)

  test({ "merges multiple maps before closing" }, function()
    -- one source says A→B; another says B→C. The union gives A→B→C.
    local r = extends_m.denormalize(9, {
      { A = set { "B" } },
      { B = set { "C" } },
    })
    T.eq(r.A, set { "A", "B", "C" })
    T.eq(r.B, set { "B", "C" })
  end)

  test({ "diamond — A→B, A→C, B→D, C→D" }, function()
    local r = extends_m.denormalize(9, {
      { A = set { "B", "C" }, B = set { "D" }, C = set { "D" } },
    })
    T.eq(r.A, set { "A", "B", "C", "D" })
    T.eq(r.B, set { "B", "D" })
    T.eq(r.C, set { "C", "D" })
  end)

  test({ "self-edge — A→A — terminates and yields {A}" }, function()
    local r = extends_m.denormalize(9, { { A = set { "A" } } })
    T.eq(r.A, set { "A" })
  end)

  test({ "two-cycle — A↔B — both closures equal {A,B}" }, function()
    local r = extends_m.denormalize(9, {
      { A = set { "B" }, B = set { "A" } },
    })
    T.eq(r.A, set { "A", "B" })
    T.eq(r.B, set { "A", "B" })
  end)

  test({ "three-cycle — A→B→C→A — full triangle" }, function()
    local r = extends_m.denormalize(9, {
      { A = set { "B" }, B = set { "C" }, C = set { "A" } },
    })
    T.eq(r.A, set { "A", "B", "C" })
    T.eq(r.B, set { "A", "B", "C" })
    T.eq(r.C, set { "A", "B", "C" })
  end)

  test({ "depth caps how far the BFS walks — chain A→B→C→D at depth=1" }, function()
    -- one hop only: A reaches B but not C/D.
    local r = extends_m.denormalize(1, {
      { A = set { "B" }, B = set { "C" }, C = set { "D" } },
    })
    T.eq(r.A, set { "A", "B" })
    T.eq(r.B, set { "B", "C" })
    T.eq(r.C, set { "C", "D" })
  end)

  test({ "depth=0 — no traversal — identity only" }, function()
    local r = extends_m.denormalize(0, { { A = set { "B", "C" } } })
    T.eq(r.A, set { "A" })
  end)

  test({ "multi-parent at one node — A→{B,C,D}" }, function()
    local r = extends_m.denormalize(9, {
      { A = set { "B", "C", "D" } },
    })
    T.eq(r.A, set { "A", "B", "C", "D" })
  end)

  test({ "does not invent entries for fts only mentioned as parents" }, function()
    -- B appears only as a parent of A; B itself has no own row in the graph
    -- and therefore no closure row in the result.
    local r = extends_m.denormalize(9, { { A = set { "B" } } })
    T.eq(r.B, nil)
  end)
end)

T.describe({ "snippets.extends.traverse" }, function(test)
  ---@param graph table<string, string[]>
  ---@return fun(t: string): { extends: string[] }
  local fetcher = function(graph)
    return function(t)
      return { extends = graph[t] or {} }
    end
  end

  ---@param target string
  ---@param graph table<string, string[]>
  ---@return string[]
  local sorted_seen = function(target, graph)
    local seen = {}
    for t, _ in extends_m.traverse(target, fetcher(graph)) do
      table.insert(seen, t)
    end
    table.sort(seen)
    return seen
  end

  test({ "yields target plus the implicit defaults" }, function()
    T.eq(sorted_seen("foo", {}), { "*", "_", "foo" })
  end)

  test({ "follows extends edges depth-first" }, function()
    T.eq(sorted_seen("A", { A = { "B" }, B = { "C" } }), { "*", "A", "B", "C", "_" })
  end)

  test({ "deduplicates already-loaded filetypes" }, function()
    -- A → B, A → C, B → C: C should not be processed twice.
    local counts = {}
    for _, t in pairs(sorted_seen("A", { A = { "B", "C" }, B = { "C" } })) do
      counts[t] = (counts[t] or 0) + 1
    end
    T.eq(counts, { ["*"] = 1, A = 1, B = 1, C = 1, _ = 1 })
  end)

  test({ "terminates on self-edge" }, function()
    T.eq(sorted_seen("A", { A = { "A" } }), { "*", "A", "_" })
  end)

  test({ "terminates on two-cycle" }, function()
    T.eq(sorted_seen("A", { A = { "B" }, B = { "A" } }), { "*", "A", "B", "_" })
  end)

  test({ "terminates on three-cycle" }, function()
    T.eq(sorted_seen("A", { A = { "B" }, B = { "C" }, C = { "A" } }), { "*", "A", "B", "C", "_" })
  end)

  test({ "implicit entries follow their own extends" }, function()
    -- "*" extends "shared"; "shared" must appear in the visited set.
    T.eq(sorted_seen("foo", { ["*"] = { "shared" } }), { "*", "_", "foo", "shared" })
  end)

  test({ "yielded cached value is whatever fetch returned" }, function()
    local fetch = function(t)
      return { extends = {}, payload = t .. "-data" }
    end
    local payloads = {}
    for t, cached in extends_m.traverse("X", fetch) do
      payloads[t] = cached.payload
    end
    T.eq(payloads, { X = "X-data", ["*"] = "*-data", _ = "_-data" })
  end)

  test({ "target deduped against implicit when they overlap" }, function()
    -- if "*" is the target, it shouldn't be visited twice.
    local counts = {}
    for _, t in pairs(sorted_seen("*", {})) do
      counts[t] = (counts[t] or 0) + 1
    end
    T.eq(counts, { ["*"] = 1, _ = 1 })
  end)
end)
