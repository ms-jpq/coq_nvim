local set = require "coq.lib.set"
local tokens = require "coq.lib.index.tokens"

-- Tiered fuzzy match: byte-exact → smart-case prefix → camelCase initialism
-- → Smith-Waterman. See .exp/README.md for tournament and rationale.
--
-- Tier table:
--   T_EXACT   2^30   needle == haystack (byte-exact)
--   T_PREFIX  2^28   smart-case prefix; sub-rank length asc, mismatch · n
--   T_CAMEL   2^24   needle == prefix of initialism(haystack); length asc, mismatch −1
--   T_FUZZY   0      fzf v2 Smith-Waterman; length tiebreak · 0.001
--
-- Smart-case is per-char: uppercase needle char requires uppercase haystack
-- char; lowercase needle char is case-folded.
--
-- File layout: helpers → stages → pipeline. Each stage shares the boundary
-- signature `(needle, haystack) -> score | nil` so the pipeline reduces to
-- "first non-nil wins".

local M = {}

local T_EXACT = 2 ^ 30
local T_PREFIX = 2 ^ 28
local T_CAMEL = 2 ^ 24

local LEN_CAP = 1024

local BYTE_A = string.byte "A"
local BYTE_Z = string.byte "Z"
local BYTE_a = string.byte "a"
local BYTE_z = string.byte "z"
local BYTE_0 = string.byte "0"
local BYTE_9 = string.byte "9"
local BYTE_HIGH = 128 -- first byte of any multi-byte UTF-8 codepoint

-- ============================================================================
-- Helpers
-- ============================================================================

local is_upper = function(b)
  return b >= BYTE_A and b <= BYTE_Z
end

local is_lower = function(b)
  return b >= BYTE_a and b <= BYTE_z
end

local is_digit = function(b)
  return b >= BYTE_0 and b <= BYTE_9
end

local to_lower = function(b)
  return is_upper(b) and b + (BYTE_a - BYTE_A) or b
end

-- Per-character smart-case predicate. The driver of the case rule:
-- lowercase needle accepts any case; uppercase needle requires exact case.
local smart_eq = function(nb, hb)
  if is_upper(nb) then
    return nb == hb
  end
  return to_lower(nb) == to_lower(hb)
end

local smart_starts_with = function(hay, ned)
  if #ned > #hay then
    return false
  end
  for i = 1, #ned do
    if not smart_eq(string.byte(ned, i), string.byte(hay, i)) then
      return false
    end
  end
  return true
end

-- camelCase / snake_case initials of a string.
-- "AnimGraphNode"        -> "AGN"
-- "anim_graph_node"      -> "agn"
-- "BatchAgnSelector"     -> "BAS"
local initials = function(s)
  local out = {}
  local prev = string.byte " " -- start of string treated as whitespace
  for i = 1, #s do
    local b = string.byte(s, i)
    local prev_word = is_lower(prev) or is_digit(prev) or is_upper(prev)
    if is_upper(b) and is_lower(prev) then
      table.insert(out, b)
    elseif not prev_word and (is_upper(b) or is_lower(b) or is_digit(b)) then
      table.insert(out, b)
    end
    prev = b
  end
  return string.char(unpack(out))
end

-- fzf v2 character classes
local CLASS_WHITE = 1
local CLASS_NONWORD = 2
local CLASS_DELIM = 3
local CLASS_LOWER = 4
local CLASS_UPPER = 5
local CLASS_LETTER = 6
local CLASS_NUMBER = 7

local DELIMITERS = set.new { string.byte "/", string.byte ",", string.byte ":", string.byte ";", string.byte "|" }

local classify = function(b)
  if tokens.WHITES[b] then
    return CLASS_WHITE
  end
  if DELIMITERS[b] then
    return CLASS_DELIM
  end
  if is_lower(b) then
    return CLASS_LOWER
  end
  if is_upper(b) then
    return CLASS_UPPER
  end
  if is_digit(b) then
    return CLASS_NUMBER
  end
  if b >= BYTE_HIGH then
    return CLASS_LETTER
  end
  return CLASS_NONWORD
end

-- fzf v2 integer u16 weights
local SCORE_MATCH = 16
local SCORE_GAP_START = -3
local SCORE_GAP_EXTENSION = -1
local BONUS_BOUNDARY = 8
local BONUS_NON_WORD = 8
local BONUS_CAMEL_123 = 7
local BONUS_CONSECUTIVE = 4
local BONUS_FIRST_CHAR_MULT = 2
local BONUS_BOUNDARY_WHITE = 10
local BONUS_BOUNDARY_DELIM = 9

-- Tier-overlap invariant. Bounds derived from the per-stage score formulas:
--   try_prefix max = T_PREFIX + full_bonus(LEN_CAP) + (LEN_CAP - m)  - 0
--   try_camel  max = T_CAMEL  + (LEN_CAP - m)
--   try_fuzzy  max = SCORE_MATCH * BONUS_FIRST_CHAR_MULT * LEN_CAP + LEN_CAP*0.001
-- Future LEN_CAP / tier bumps trip these at module load.
do
  local FUZZY_MAX = SCORE_MATCH * BONUS_FIRST_CHAR_MULT * LEN_CAP + LEN_CAP
  assert(T_PREFIX + 2 * LEN_CAP < T_EXACT, "try_prefix can overlap T_EXACT")
  assert(T_CAMEL + LEN_CAP < T_PREFIX, "try_camel can overlap T_PREFIX")
  assert(FUZZY_MAX < T_CAMEL, "try_fuzzy can overlap T_CAMEL")
end

local bonus_for = function(prev, curr)
  if curr == CLASS_LOWER or curr == CLASS_LETTER or curr == CLASS_UPPER or curr == CLASS_NUMBER then
    if prev == CLASS_WHITE then
      return BONUS_BOUNDARY_WHITE
    end
    if prev == CLASS_DELIM then
      return BONUS_BOUNDARY_DELIM
    end
    if prev == CLASS_NONWORD then
      return BONUS_BOUNDARY
    end
  end
  if prev == CLASS_LOWER and curr == CLASS_UPPER then
    return BONUS_CAMEL_123
  end
  if curr == CLASS_NUMBER and prev ~= CLASS_NUMBER then
    return BONUS_CAMEL_123
  end
  if curr == CLASS_NONWORD or curr == CLASS_DELIM then
    return BONUS_NON_WORD
  end
  if curr == CLASS_WHITE then
    return BONUS_BOUNDARY_WHITE
  end
  return 0
end

---Subsequence pre-check — true iff every needle byte appears in order in
---haystack. Cheap rejection before the O(n·m) DP.
---@param probe hybrid.Probe
---@return boolean
local is_subsequence = function(probe)
  local needle, haystack, n, m = probe.needle, probe.haystack, probe.n, probe.m
  local i = 1
  for j = 1, m do
    if smart_eq(string.byte(needle, i), string.byte(haystack, j)) then
      i = i + 1
      if i > n then
        return true
      end
    end
  end
  return false
end

---Pre-classify each haystack byte once; the DP reads from this table by index.
---@param haystack string
---@param m integer
---@return integer[]
local classify_haystack = function(haystack, m)
  local hclass = {}
  for j = 1, m do
    hclass[j] = classify(string.byte(haystack, j))
  end
  return hclass
end

---fzf v2 Smith-Waterman DP. Two matrices: H (best score), C (consecutive-run
---length). Returns the maximum alignment score over the final row.
---@param probe hybrid.Probe
---@param hclass integer[]
---@return integer
local dp_score = function(probe, hclass)
  local needle, haystack, n, m = probe.needle, probe.haystack, probe.n, probe.m

  local H, C = {}, {}
  for i = 0, n do
    H[i] = {}
    C[i] = {}
    H[i][0] = 0
    C[i][0] = 0
  end
  for j = 0, m do
    H[0][j] = 0
    C[0][j] = 0
  end

  local best = 0
  for i = 1, n do
    local in_gap = false
    for j = 1, m do
      local left = H[i][j - 1]
      local s2 = left + (in_gap and SCORE_GAP_EXTENSION or SCORE_GAP_START)
      local s1 = 0
      local consec = 0

      if smart_eq(string.byte(needle, i), string.byte(haystack, j)) then
        local prev_class = (j == 1) and CLASS_WHITE or hclass[j - 1]
        local b = bonus_for(prev_class, hclass[j])
        if i == 1 then
          b = b * BONUS_FIRST_CHAR_MULT
        end
        local diag = H[i - 1][j - 1]
        consec = C[i - 1][j - 1] + 1
        if consec > 1 then
          local run_prev_class = (j - consec == 0) and CLASS_WHITE or hclass[j - consec]
          local first_b = bonus_for(run_prev_class, hclass[j - consec + 1])
          if i == 1 then
            first_b = first_b * BONUS_FIRST_CHAR_MULT
          end
          if b >= BONUS_BOUNDARY and b > first_b then
            consec = 1
          else
            b = math.max(b, BONUS_CONSECUTIVE, first_b)
          end
        end
        s1 = diag + SCORE_MATCH + b
        if s1 < s2 then
          s1 = left
          consec = 0
        end
      end

      local h
      if s1 > s2 then
        h = s1
        in_gap = false
      else
        h = s2
        in_gap = true
        if h < 0 then
          h = 0
        end
      end

      H[i][j] = h
      C[i][j] = consec
      if i == n and h > best then
        best = h
      end
    end
  end

  return best
end

---fzf v2 Smith-Waterman score, or nil if the needle isn't a subsequence.
---@param probe hybrid.Probe
---@return integer?
local fzf_score = function(probe)
  if not is_subsequence(probe) then
    return nil
  end
  local hclass = probe.hclass or classify_haystack(probe.haystack, probe.m)
  return dp_score(probe, hclass)
end

---A needle-haystack pair that has passed length validation. Each stage
---can rely on `n > 0`, `n <= m`, `m <= LEN_CAP` without re-checking.
---@class hybrid.Probe
---@field needle string
---@field haystack string
---@field n integer
---@field m integer
---@field initials_str? string
---@field hclass? integer[]

---@class hybrid.Precomputed
---@field initials_str string
---@field hclass integer[]

---@alias hybrid.Stage fun(probe: hybrid.Probe): number?

---Precompute the haystack-only inputs (initials, fzf class array) once per
---haystack. Callers that score the same haystack many times — e.g. a fuzzy
---bucket scored against many needles — store this alongside the item and
---pass it back into `score` to skip the per-call rebuild.
---@param haystack string
---@return hybrid.Precomputed?
M.precompute = function(haystack)
  local m = #haystack
  if m == 0 or m > LEN_CAP then
    return nil
  end
  return { initials_str = initials(haystack), hclass = classify_haystack(haystack, m) }
end

---Construct a Probe from raw inputs. Returns nil for empty / oversize.
---Acts as the pipeline's gate — invalid inputs never reach any stage.
---Exposed for tests; callers should go through M.score.
---@param needle string
---@param haystack string
---@param precomputed? hybrid.Precomputed
---@return hybrid.Probe?
M._probe_of = function(needle, haystack, precomputed)
  local n, m = #needle, #haystack
  if n == 0 or n > m or m > LEN_CAP then
    return nil
  end
  return {
    needle = needle,
    haystack = haystack,
    n = n,
    m = m,
    initials_str = precomputed and precomputed.initials_str,
    hclass = precomputed and precomputed.hclass,
  }
end

-- ============================================================================
-- Stages
--
-- Each stage: hybrid.Stage = (probe) -> score | nil.
-- `nil` means "this stage does not match"; a non-nil score is final for
-- that stage. The pipeline returns the first non-nil.
-- ============================================================================

---@type hybrid.Stage
local try_exact = function(probe)
  if probe.needle == probe.haystack then
    return T_EXACT
  end
  return nil
end

---@type hybrid.Stage
local try_prefix = function(probe)
  local needle, haystack, n, m = probe.needle, probe.haystack, probe.n, probe.m
  if not smart_starts_with(haystack, needle) then
    return nil
  end
  local mismatches = 0
  for i = 1, n do
    if string.byte(needle, i) ~= string.byte(haystack, i) then
      mismatches = mismatches + 1
    end
  end
  local full_bonus = (n == m) and LEN_CAP or 0
  return T_PREFIX + full_bonus + (LEN_CAP - m) - n * mismatches
end

---@type hybrid.Stage
local try_camel = function(probe)
  local needle, n, m = probe.needle, probe.n, probe.m
  local inits = probe.initials_str or initials(probe.haystack)
  if #inits < n then
    return nil
  end
  local mismatches = 0
  for i = 1, n do
    local nb, hb = string.byte(needle, i), string.byte(inits, i)
    if not smart_eq(nb, hb) then
      return nil
    end
    if nb ~= hb then
      mismatches = mismatches + 1
    end
  end
  return T_CAMEL + (LEN_CAP - m) - mismatches
end

---@type hybrid.Stage
local try_fuzzy = function(probe)
  local f = fzf_score(probe)
  if f == nil then
    return nil
  end
  -- 0.001 length tiebreak deliberately lives below integer granularity, so
  -- the fractional part can never tie or exceed the next-higher integer
  -- score. Two haystacks with the same fzf score sort by length asc.
  -- This is the one stage whose `number?` is a float; the other tiers are
  -- always integer. Pipeline comparisons mix cleanly under Lua semantics.
  return f + (LEN_CAP - probe.m) * 0.001
end

-- ============================================================================
-- Pipeline
-- ============================================================================

---Exposed for tests; callers should go through M.score.
---@type table<string, hybrid.Stage>
M._STAGES = {
  exact = try_exact,
  prefix = try_prefix,
  camel = try_camel,
  fuzzy = try_fuzzy,
}

local STAGE_ORDER = { "exact", "prefix", "camel", "fuzzy" }

---@param needle string
---@param haystack string
---@param precomputed? hybrid.Precomputed
---@return number?
M.score = function(needle, haystack, precomputed)
  local probe = M._probe_of(needle, haystack, precomputed)
  if probe == nil then
    return nil
  end
  for _, name in ipairs(STAGE_ORDER) do
    local s = M._STAGES[name](probe)
    if s ~= nil then
      return s
    end
  end
  return nil
end

return M
