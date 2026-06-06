local T = require "coq.lib.test"
local extends_m = require "coq.producers.snippets.extends"

---@param parents string[]
---@return lib.Set<string>
local set = function(parents)
  local s = {}
  for _, p in pairs(parents) do
    s[p] = true
  end
  return s
end

T.describe("snippets.extends.denormalize", function(test)
  test("empty input → empty result", function()
    T.eq(extends_m.denormalize(9, {}), {})
  end)

  test("each filetype includes itself", function()
    -- A → B; identity reflex means A is in its own closure too.
    local r = extends_m.denormalize(9, { { A = set { "B" } } })
    T.eq(r.A, set { "A", "B" })
  end)

  test("transitive — A→B→C produces A's closure {A,B,C}", function()
    local r = extends_m.denormalize(9, {
      { A = set { "B" }, B = set { "C" } },
    })
    T.eq(r.A, set { "A", "B", "C" })
    T.eq(r.B, set { "B", "C" })
  end)

  test("merges multiple maps before closing", function()
    -- one source says A→B; another says B→C. The union gives A→B→C.
    local r = extends_m.denormalize(9, {
      { A = set { "B" } },
      { B = set { "C" } },
    })
    T.eq(r.A, set { "A", "B", "C" })
    T.eq(r.B, set { "B", "C" })
  end)

  test("diamond — A→B, A→C, B→D, C→D", function()
    local r = extends_m.denormalize(9, {
      { A = set { "B", "C" }, B = set { "D" }, C = set { "D" } },
    })
    T.eq(r.A, set { "A", "B", "C", "D" })
    T.eq(r.B, set { "B", "D" })
    T.eq(r.C, set { "C", "D" })
  end)

  test("self-edge — A→A — terminates and yields {A}", function()
    local r = extends_m.denormalize(9, { { A = set { "A" } } })
    T.eq(r.A, set { "A" })
  end)

  test("two-cycle — A↔B — both closures equal {A,B}", function()
    local r = extends_m.denormalize(9, {
      { A = set { "B" }, B = set { "A" } },
    })
    T.eq(r.A, set { "A", "B" })
    T.eq(r.B, set { "A", "B" })
  end)

  test("three-cycle — A→B→C→A — full triangle", function()
    local r = extends_m.denormalize(9, {
      { A = set { "B" }, B = set { "C" }, C = set { "A" } },
    })
    T.eq(r.A, set { "A", "B", "C" })
    T.eq(r.B, set { "A", "B", "C" })
    T.eq(r.C, set { "A", "B", "C" })
  end)

  test("depth caps how far the BFS walks — chain A→B→C→D at depth=1", function()
    -- one hop only: A reaches B but not C/D.
    local r = extends_m.denormalize(1, {
      { A = set { "B" }, B = set { "C" }, C = set { "D" } },
    })
    T.eq(r.A, set { "A", "B" })
    T.eq(r.B, set { "B", "C" })
    T.eq(r.C, set { "C", "D" })
  end)

  test("depth=0 — no traversal — identity only", function()
    local r = extends_m.denormalize(0, { { A = set { "B", "C" } } })
    T.eq(r.A, set { "A" })
  end)

  test("multi-parent at one node — A→{B,C,D}", function()
    local r = extends_m.denormalize(9, {
      { A = set { "B", "C", "D" } },
    })
    T.eq(r.A, set { "A", "B", "C", "D" })
  end)

  test("does not invent entries for fts only mentioned as parents", function()
    -- B appears only as a parent of A; B itself has no own row in the graph
    -- and therefore no closure row in the result.
    local r = extends_m.denormalize(9, { { A = set { "B" } } })
    T.eq(r.B, nil)
  end)
end)
