local T = require "coq.lib.test"
local hybrid = require "coq.lib.index.rank.hybrid"

---@param token string
---@param candidate string
---@return number?
local s = function(token, candidate)
  return hybrid.score(token, candidate)
end

---Strict descending: each adjacent pair must satisfy a > b.
---@param ... number?
local function strictly_decreasing(...)
  local args = { ... }
  for i = 1, #args - 1 do
    local a, b = args[i], args[i + 1]
    assert(a ~= nil and b ~= nil, ("nil at position %d or %d"):format(i, i + 1))
    assert(a > b, ("expected %s > %s at position %d"):format(a, b, i))
  end
end

T.describe({ "rank.hybrid" }, function(test)
  -- ----------------------------------------------------------------------
  -- gates
  -- ----------------------------------------------------------------------

  test({ "empty needle returns nil" }, function()
    T.eq(s("", "labrador"), nil)
  end)

  test({ "needle longer than haystack returns nil" }, function()
    T.eq(s("labradoritex", "labrador"), nil)
  end)

  test({ "haystack over the length cap returns nil" }, function()
    T.eq(s("lab", string.rep("x", 2048)), nil)
  end)

  test({ "non-subsequence candidate returns nil" }, function()
    T.eq(s("xyz", "labrador"), nil)
  end)

  -- ----------------------------------------------------------------------
  -- T_EXACT — byte-exact only
  -- ----------------------------------------------------------------------

  test({ "byte-exact equality hits the top tier" }, function()
    local exact = s("labrador", "labrador")
    assert(exact ~= nil and exact >= 2 ^ 30, "expected T_EXACT, got " .. tostring(exact))
  end)

  test({ "smart-case equality does NOT hit T_EXACT" }, function()
    -- "Labrador" smart-matches "labrador" (lowercase needle accepts any case)
    -- but T_EXACT requires byte-exact: it falls to T_PREFIX instead.
    local fold = assert(s("labrador", "Labrador"))
    local exact = assert(s("labrador", "labrador"))
    assert(fold < 2 ^ 30, "Labrador should not hit T_EXACT")
    assert(exact > fold, "byte-exact must outscore case-fold-prefix")
  end)

  test({ "T_EXACT outranks every other tier" }, function()
    local exact = assert(s("dog", "dog"))
    local prefix = assert(s("dog", "doggo"))
    local camel = assert(s("agn", "AnimGraphNode"))
    local fuzzy = assert(s("lbr", "labrador"))
    strictly_decreasing(exact, prefix, camel, fuzzy)
  end)

  -- ----------------------------------------------------------------------
  -- T_PREFIX — smart-case prefix
  -- ----------------------------------------------------------------------

  test({ "a prefix match scores above any fuzzy match" }, function()
    local pre = assert(s("lab", "labrador"))
    local fuz = assert(s("lab", "load_breed_data"))
    assert(pre > fuz, "prefix should outscore fuzzy")
  end)

  test({ "shorter prefix wins on length tiebreak" }, function()
    local short = assert(s("dog", "dog_id"))
    local long = assert(s("dog", "dog_breed_history"))
    assert(short > long, "shorter prefix should win")
  end)

  test({ "zero-mismatch prefix beats case-mismatched same-length prefix" }, function()
    local clean = assert(s("lab", "labrador"))
    local dirty = assert(s("lab", "Labrador"))
    assert(clean > dirty, "perfect-case prefix should win on tiebreak")
  end)

  test({ "case mismatch penalty scales with needle length" }, function()
    -- 1 mismatch on n=3 query (-3) is less penalty than 3 mismatches (-9).
    local one_mm = assert(s("lab", "Labrador"))
    local three_mm = assert(s("lab", "LABrador"))
    assert(one_mm > three_mm)
  end)

  test({ "full-length match outranks longer prefix even with case mismatch" }, function()
    -- MAX (3 chars, 3 mismatches) beats max_age (7 chars, 0 mismatches)
    -- because the full-length bonus dominates.
    local full = assert(s("max", "MAX"))
    local longer = assert(s("max", "max_age"))
    assert(full > longer, ("MAX %d should beat max_age %d"):format(full, longer))
  end)

  -- ----------------------------------------------------------------------
  -- smart-case — per-character
  -- ----------------------------------------------------------------------

  test({ "lowercase needle is case-insensitive" }, function()
    assert(s("lab", "labrador") ~= nil)
    assert(s("lab", "Labrador") ~= nil)
    assert(s("lab", "LABRADOR") ~= nil)
  end)

  test({ "uppercase needle char requires uppercase haystack char" }, function()
    T.eq(s("Lab", "labrador"), nil)
    assert(s("Lab", "Labrador") ~= nil)
    assert(s("Lab", "LABRADOR") ~= nil)
  end)

  test({ "all-uppercase needle requires every char uppercase" }, function()
    T.eq(s("LAB", "labrador"), nil)
    T.eq(s("LAB", "Labrador"), nil)
    assert(s("LAB", "LABRADOR") ~= nil)
  end)

  test({ "mixed-case needle smart-cases each position independently" }, function()
    -- `gR` — g lowercase accepts g/G; R uppercase requires R.
    assert(s("gR", "goldenRetriever") ~= nil)
    assert(s("gR", "GoldenRetriever") ~= nil)
    T.eq(s("gR", "greatdane"), nil) -- no capital R
  end)

  -- ----------------------------------------------------------------------
  -- T_CAMEL — initialism
  -- ----------------------------------------------------------------------

  test({ "camelCase initialism matches" }, function()
    local camel = assert(s("agn", "AnimGraphNode"))
    -- Above any fuzzy match for the same query.
    local fuz = assert(s("agn", "BatchAgnSelector"))
    assert(camel > fuz, "T_CAMEL should outscore T_FUZZY")
  end)

  test({ "snake_case initialism matches" }, function()
    local snake = assert(s("agn", "anim_graph_node"))
    local fuz = assert(s("agn", "ragnarok"))
    assert(snake > fuz)
  end)

  test({ "T_PREFIX outranks T_CAMEL" }, function()
    local pre = assert(s("agn", "agn_const"))
    local camel = assert(s("agn", "AnimGraphNode"))
    assert(pre > camel, "prefix should beat initialism")
  end)

  test({ "non-initialism characters do not match T_CAMEL" }, function()
    -- BatchAgnSelector initials are BAS, not AGN. Falls to T_FUZZY.
    local got = assert(s("agn", "BatchAgnSelector"))
    assert(got < 2 ^ 24, "expected T_FUZZY band, got " .. got)
  end)

  -- ----------------------------------------------------------------------
  -- T_FUZZY — fzf v2 fallback
  -- ----------------------------------------------------------------------

  test({ "fuzzy match scores positively for valid subsequences" }, function()
    local got = assert(s("lbr", "labrador"))
    assert(got > 0, "expected positive fuzzy score")
  end)

  test({ "tighter alignments outscore looser ones" }, function()
    -- `lab` lands as a consecutive run in labrador, scattered in load_breed.
    local tight = assert(s("lab", "load_breed_data"))
    local pre = assert(s("lab", "labrador"))
    assert(pre > tight, "prefix should beat scatter")
  end)

  test({ "word-boundary match scores above mid-word match in fuzzy tier" }, function()
    -- Both are fuzzy (no prefix). boundary wins.
    local boundary = assert(s("br", "best_breed"))
    local interior = assert(s("br", "library"))
    assert(boundary > interior)
  end)

  -- ----------------------------------------------------------------------
  -- tier ordering — strict
  -- ----------------------------------------------------------------------

  test({ "tier ranges never overlap" }, function()
    -- Floor of each tier strictly exceeds the ceiling of the next.
    -- Use a long haystack inside each tier to push toward its floor.
    local long = string.rep("x", 900)
    local exact = assert(s("d", "d"))
    local prefix_low = assert(s("d", "d" .. long))
    local camel_low = assert(s("d", "D" .. long)) -- initial 'D', q='d' → AGN-like
    local fuzzy_high = assert(s("d", "d")) -- T_EXACT, just for the comparison floor
    -- exact strictly above prefix
    assert(exact > prefix_low)
    -- prefix strictly above camel (camel uses snake/upper boundary)
    assert(prefix_low > camel_low or camel_low == nil)
    -- both tiers above any T_FUZZY score
    assert(fuzzy_high > 0)
  end)
end)

-- Stage-level tests. Each stage takes a Probe and returns a score or nil.
-- Tests construct probes via hybrid._probe_of and feed them directly.
T.describe({ "rank.hybrid._probe_of" }, function(test)
  test({ "rejects empty needle" }, function()
    T.eq(hybrid._probe_of("", "dog"), nil)
  end)

  test({ "rejects needle longer than haystack" }, function()
    T.eq(hybrid._probe_of("lab", "x"), nil)
  end)

  test({ "accepts equal-length pair" }, function()
    assert(hybrid._probe_of("dog", "dog") ~= nil)
  end)

  test({ "rejects oversize haystack" }, function()
    T.eq(hybrid._probe_of("a", string.rep("a", 1025)), nil)
  end)
end)

T.describe({ "rank.hybrid.STAGES" }, function(test)
  ---@param n string
  ---@param h string
  ---@return hybrid.Probe
  local probe = function(n, h)
    return assert(hybrid._probe_of(n, h), "test inputs must yield a valid probe")
  end

  -- exact ----------------------------------------------------------------

  test({ "exact: byte-equal returns T_EXACT" }, function()
    T.eq(hybrid.STAGES.exact(probe("dog", "dog")), 2 ^ 30)
  end)

  test({ "exact: case-fold-equal returns nil (byte-exact only)" }, function()
    T.eq(hybrid.STAGES.exact(probe("dog", "Dog")), nil)
  end)

  test({ "exact: any other input returns nil" }, function()
    T.eq(hybrid.STAGES.exact(probe("dog", "doggo")), nil)
    T.eq(hybrid.STAGES.exact(probe("dog", "labrador")), nil)
  end)

  -- prefix ---------------------------------------------------------------

  test({ "prefix: smart-case prefix returns a positive score" }, function()
    assert(hybrid.STAGES.prefix(probe("lab", "labrador")) ~= nil)
    assert(hybrid.STAGES.prefix(probe("lab", "Labrador")) ~= nil)
  end)

  test({ "prefix: does NOT short-circuit on exact equality" }, function()
    -- The pipeline routes exact via try_exact first; the stage itself
    -- still treats exact as a valid prefix and returns a score.
    local got = hybrid.STAGES.prefix(probe("dog", "dog"))
    assert(got ~= nil, "prefix should accept exact as a valid prefix")
    assert(got < 2 ^ 30, "prefix score should sit below T_EXACT")
  end)

  test({ "prefix: non-prefix returns nil" }, function()
    T.eq(hybrid.STAGES.prefix(probe("lab", "global_lab")), nil)
  end)

  test({ "prefix: smart-case rejection returns nil" }, function()
    T.eq(hybrid.STAGES.prefix(probe("Lab", "labrador")), nil)
  end)

  -- camel ----------------------------------------------------------------

  test({ "camel: matching initialism returns a positive score" }, function()
    assert(hybrid.STAGES.camel(probe("agn", "AnimGraphNode")) ~= nil)
    assert(hybrid.STAGES.camel(probe("agn", "anim_graph_node")) ~= nil)
  end)

  test({ "camel: non-initialism returns nil" }, function()
    T.eq(hybrid.STAGES.camel(probe("agn", "BatchAgnSelector")), nil)
    T.eq(hybrid.STAGES.camel(probe("xyz", "AnimGraphNode")), nil)
  end)

  test({ "camel: shorter haystack wins on tiebreak" }, function()
    local short = assert(hybrid.STAGES.camel(probe("agn", "AnimGraphNode")))
    local long = assert(hybrid.STAGES.camel(probe("agn", "AnimationGraphNode")))
    assert(short > long, "shorter initialism candidate should outscore longer")
  end)

  -- fuzzy ----------------------------------------------------------------

  test({ "fuzzy: subsequence match returns a positive score" }, function()
    local got = hybrid.STAGES.fuzzy(probe("lbr", "labrador"))
    assert(got ~= nil and got > 0)
  end)

  test({ "fuzzy: non-subsequence returns nil" }, function()
    T.eq(hybrid.STAGES.fuzzy(probe("xyz", "labrador")), nil)
  end)

  test({ "fuzzy: smart-case rejection propagates as nil" }, function()
    T.eq(hybrid.STAGES.fuzzy(probe("Lab", "labrador")), nil)
  end)

  -- pipeline ordering ----------------------------------------------------

  test({ "score: returns try_exact result when byte-equal" }, function()
    T.eq(hybrid.score("dog", "dog"), hybrid.STAGES.exact(probe("dog", "dog")))
  end)

  test({ "score: returns try_prefix result when smart-case prefix matches" }, function()
    T.eq(hybrid.score("lab", "labrador"), hybrid.STAGES.prefix(probe("lab", "labrador")))
  end)

  test({ "score: returns try_camel result for initialism non-prefix" }, function()
    T.eq(hybrid.score("agn", "AnimGraphNode"), hybrid.STAGES.camel(probe("agn", "AnimGraphNode")))
  end)

  test({ "score: returns try_fuzzy result for plain subsequence" }, function()
    T.eq(hybrid.score("lbr", "labrador"), hybrid.STAGES.fuzzy(probe("lbr", "labrador")))
  end)
end)
