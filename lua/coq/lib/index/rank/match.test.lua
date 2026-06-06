local T = require "coq.lib.test"
local match = require "coq.lib.index.rank.match"

-- Tests run on the main thread, so match.score takes the direct (non-worker)
-- path through vim.fn.matchfuzzypos.
T.describe("rank.match", function(test)
  test("a matching candidate scores above zero", function()
    local score = match.score("gold", "golden_retriever")
    assert(score > 0, "expected a positive score, got " .. tostring(score))
  end)

  test("a non-matching candidate scores zero", function()
    T.eq(match.score("xyz", "golden_retriever"), 0)
  end)

  test("an empty token scores zero (and never touches matchfuzzypos)", function()
    T.eq(match.score("", "golden_retriever"), 0)
  end)

  test("a tighter match outscores a looser one", function()
    local tight = match.score("lab", "labrador")
    local loose = match.score("lbr", "labrador")
    assert(tight > loose, ("tight %d should beat loose %d"):format(tight, loose))
  end)

  test("lowercase query is case-insensitive", function()
    assert(match.score("lab", "Labrador") > 0)
    assert(match.score("lab", "LABRADOR") > 0)
  end)

  test("uppercase in query enables smart-case (rejects case mismatch)", function()
    T.eq(match.score("Lab", "labrador"), 0)
    assert(match.score("Lab", "Labrador") > 0)
  end)

  test("all-uppercase query requires all-uppercase candidate", function()
    T.eq(match.score("LAB", "Labrador"), 0)
    T.eq(match.score("LAB", "labrador"), 0)
    assert(match.score("LAB", "LABRADOR") > 0)
  end)
end)
