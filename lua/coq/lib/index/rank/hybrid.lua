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

-- ============================================================================
-- Helpers
-- ============================================================================

local function is_upper(b)
  return b >= 65 and b <= 90
end

local function is_lower(b)
  return b >= 97 and b <= 122
end

local function to_lower(b)
  return is_upper(b) and b + 32 or b
end

-- Per-character smart-case predicate. The driver of the case rule:
-- lowercase needle accepts any case; uppercase needle requires exact case.
local function smart_eq(nb, hb)
  if is_upper(nb) then
    return nb == hb
  end
  return to_lower(nb) == to_lower(hb)
end

local function smart_starts_with(hay, ned)
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

local function smart_string_eq(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if not smart_eq(string.byte(a, i), string.byte(b, i)) then
      return false
    end
  end
  return true
end

-- camelCase / snake_case initials of a string.
-- "AnimGraphNode"        -> "AGN"
-- "anim_graph_node"      -> "agn"
-- "BatchAgnSelector"     -> "BAS"
local function initials(s)
  local out = {}
  local prev = 32 -- start of string treated as whitespace
  for i = 1, #s do
    local b = string.byte(s, i)
    local prev_lower = is_lower(prev) or (prev >= 48 and prev <= 57)
    local prev_word = prev_lower or is_upper(prev)
    if is_upper(b) and is_lower(prev) then
      table.insert(out, b)
    elseif not prev_word and (is_upper(b) or is_lower(b) or (b >= 48 and b <= 57)) then
      table.insert(out, b)
    end
    prev = b
  end
  return string.char((table.unpack or unpack)(out))
end

-- fzf v2 character classes
local CLASS_WHITE = 1
local CLASS_NONWORD = 2
local CLASS_DELIM = 3
local CLASS_LOWER = 4
local CLASS_UPPER = 5
local CLASS_LETTER = 6
local CLASS_NUMBER = 7

local DELIMITERS = { [47] = true, [44] = true, [58] = true, [59] = true, [124] = true }
local WHITES = { [32] = true, [9] = true, [10] = true, [13] = true }

local function classify(b)
  if WHITES[b] then
    return CLASS_WHITE
  end
  if DELIMITERS[b] then
    return CLASS_DELIM
  end
  if b >= 97 and b <= 122 then
    return CLASS_LOWER
  end
  if b >= 65 and b <= 90 then
    return CLASS_UPPER
  end
  if b >= 48 and b <= 57 then
    return CLASS_NUMBER
  end
  if b >= 128 then
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

local function bonus_for(prev, curr)
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

---fzf v2 Smith-Waterman DP. Returns the maximum alignment score or nil
---when no subsequence match exists.
---@param needle string
---@param haystack string
---@return integer?
local function fzf_score(needle, haystack)
  local n, m = #needle, #haystack

  local function nmatch(i, j)
    return smart_eq(string.byte(needle, i), string.byte(haystack, j))
  end

  -- subsequence pre-check
  do
    local i = 1
    for j = 1, m do
      if nmatch(i, j) then
        i = i + 1
        if i > n then
          break
        end
      end
    end
    if i <= n then
      return nil
    end
  end

  -- precompute haystack classes
  local hclass = {}
  for j = 1, m do
    hclass[j] = classify(string.byte(haystack, j))
  end

  local function bclass_at(j)
    if j == 0 then
      return CLASS_WHITE
    end
    return hclass[j]
  end

  -- DP with two matrices: H (best score) and C (consecutive-run length).
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

  local best = -1
  for i = 1, n do
    local in_gap = false
    for j = 1, m do
      local left = H[i][j - 1] or 0
      local s2 = left + (in_gap and SCORE_GAP_EXTENSION or SCORE_GAP_START)
      local s1 = 0
      local consec = 0

      if nmatch(i, j) then
        local b = bonus_for(bclass_at(j - 1), hclass[j])
        if i == 1 then
          b = b * BONUS_FIRST_CHAR_MULT
        end
        local diag = H[i - 1][j - 1] or 0
        consec = (C[i - 1][j - 1] or 0) + 1
        if consec > 1 then
          local first_b = bonus_for(bclass_at(j - consec), hclass[j - consec + 1])
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

  if best < 0 then
    return nil
  end
  return best
end

---Pipeline-level gate. Rejects empty needles, oversized needles, and
---haystacks beyond the length cap before any stage runs.
---@param needle string
---@param haystack string
---@return boolean
local function validate(needle, haystack)
  local n, m = #needle, #haystack
  return n > 0 and n <= m and m <= LEN_CAP
end

-- ============================================================================
-- Stages
--
-- Each stage: (needle, haystack) -> score | nil.
-- `nil` means "this stage does not match"; a non-nil score is final for
-- that stage. The pipeline returns the first non-nil.
-- ============================================================================

---@param needle string
---@param haystack string
---@return number?
local function try_exact(needle, haystack)
  if needle == haystack then
    return T_EXACT
  end
  return nil
end

---@param needle string
---@param haystack string
---@return number?
local function try_prefix(needle, haystack)
  if not smart_starts_with(haystack, needle) then
    return nil
  end
  local n, m = #needle, #haystack
  local mismatches = 0
  for i = 1, n do
    if string.byte(needle, i) ~= string.byte(haystack, i) then
      mismatches = mismatches + 1
    end
  end
  local full_bonus = (n == m) and LEN_CAP or 0
  return T_PREFIX + full_bonus + (LEN_CAP - m) - n * mismatches
end

---@param needle string
---@param haystack string
---@return number?
local function try_camel(needle, haystack)
  local n, m = #needle, #haystack
  local inits_pref = string.sub(initials(haystack), 1, n)
  if not smart_string_eq(needle, inits_pref) then
    return nil
  end
  local mismatches = 0
  for i = 1, n do
    if string.byte(needle, i) ~= string.byte(inits_pref, i) then
      mismatches = mismatches + 1
    end
  end
  return T_CAMEL + (LEN_CAP - m) - mismatches
end

---@param needle string
---@param haystack string
---@return number?
local function try_fuzzy(needle, haystack)
  local f = fzf_score(needle, haystack)
  if f == nil then
    return nil
  end
  return f + (LEN_CAP - #haystack) * 0.001
end

-- ============================================================================
-- Pipeline
-- ============================================================================

local STAGES = { try_exact, try_prefix, try_camel, try_fuzzy }

---@param needle string
---@param haystack string
---@return number?
M.score = function(needle, haystack)
  if not validate(needle, haystack) then
    return nil
  end
  for _, stage in pairs(STAGES) do
    local s = stage(needle, haystack)
    if s ~= nil then
      return s
    end
  end
  return nil
end

---Stages exposed for direct testing. Callers should still use `M.score`.
M._stages = {
  exact = try_exact,
  prefix = try_prefix,
  camel = try_camel,
  fuzzy = try_fuzzy,
}

return M
