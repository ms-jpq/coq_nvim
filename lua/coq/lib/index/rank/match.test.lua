local T = require "coq.lib.test"
local match = require "coq.lib.index.rank.match"

T.describe({ "rank.match" }, function(test)
  ---@type [string, string, integer, integer, number][]
  local cases = {
    { "", "dog", 3, 0, 0 },
    { "dog", "dog", 0, 3, 1 },
    { "dgo", "dog", 1, 1, 2 / 3 },
    { "ca", "abc", 2, 0, 0.5 },
    { "犬", "犬猫", 1, 1, 1 },
  }
  for _, case in ipairs(cases) do
    test({ "v1 distance and metrics", case[1], case[2] }, function()
      local lhs, rhs, distance, prefix, similarity = unpack(case)
      T.eq(match.damerau_levenshtein(lhs, rhs), distance)
      local actual = match.metrics(2, lhs, rhs)
      T.eq(actual.prefix_matches, prefix)
      assert(math.abs(actual.edit_distance - similarity) < 1e-12)
    end)
  end
  ---@type [string, string, integer][]
  local distance_cases = {
    { "", "", 0 },
    { "dog", "", 3 },
    { "dog", "dogs", 1 },
    { "dog", "dig", 1 },
    { "dog", "dgo", 1 },
    { "abc", "ca", 2 },
    { "aab", "aba", 1 },
    { "犬猫", "猫犬", 1 },
  }
  for _, case in ipairs(distance_cases) do
    test({ "Damerau-Levenshtein distance", case[1], case[2] }, function()
      local lhs, rhs, expected = unpack(case)
      T.eq(match.damerau_levenshtein(lhs, rhs), expected)
    end)
  end
  test({ "a matching candidate scores above zero" }, function()
    local score = match.score(2, "gold", "golden_retriever")
    assert(score > 0, "expected a positive score, got " .. tostring(score))
  end)

  test({ "a non-matching candidate scores zero" }, function()
    T.eq(match.score(2, "xyz", "golden_retriever"), 0)
  end)

  test({ "an empty retrieval token scores zero" }, function()
    T.eq(match.score(2, "", "golden_retriever"), 0)
  end)

  test({ "a tighter match outscores a looser one" }, function()
    local tight = match.score(2, "lab", "labrador")
    local loose = match.score(2, "lbr", "labrador")
    assert(tight > loose, ("tight %d should beat loose %d"):format(tight, loose))
  end)

  test({ "lowercase query is case-insensitive" }, function()
    assert(match.score(2, "lab", "Labrador") > 0)
    assert(match.score(2, "lab", "LABRADOR") > 0)
  end)

  test({ "uppercase in query counts case mismatches as edits" }, function()
    T.eq(match.score(2, "Lab", "labrador"), 1 / 3)
    assert(match.score(2, "Lab", "Labrador") > 0)
  end)

  test({ "all-uppercase query requires all-uppercase candidate" }, function()
    T.eq(match.score(2, "LAB", "Labrador"), 1 / 3)
    T.eq(match.score(2, "LAB", "labrador"), 0)
    assert(match.score(2, "LAB", "LABRADOR") > 0)
  end)
end)
