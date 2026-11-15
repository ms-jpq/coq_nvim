local M = {}

---@param text string
---@return string[]
local chars = function(text)
  return vim.iter(string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*")):totable()
end

---@param lhs string[]
---@param rhs string[]
---@return integer
local prefix = function(lhs, rhs)
  local count = 0
  for i = 1, math.min(#lhs, #rhs) do
    if lhs[i] ~= rhs[i] then
      break
    end
    count = count + 1
  end
  return count
end

---@param look_ahead integer
---@param lhs string[]
---@param rhs string[]
---@return number
local multiset = function(look_ahead, lhs, rhs)
  local shorter = math.min(#lhs, #rhs)
  if shorter == 0 then
    return 1
  end
  local limit = shorter + look_ahead
  local left, right = math.min(#lhs, limit), math.min(#rhs, limit)
  local counts = {}
  for i = 1, left do
    counts[lhs[i]] = (counts[lhs[i]] or 0) + 1
  end
  local common = 0
  for i = 1, right do
    local count = counts[rhs[i]] or 0
    if count > 0 then
      common = common + 1
      counts[rhs[i]] = count - 1
    end
  end
  return common / shorter
end

---@param lhs string[]
---@param rhs string[]
---@return integer
local damerau_levenshtein = function(lhs, rhs)
  local n, m = #lhs, #rhs
  local d, seen = { [0] = { [0] = n + m } }, {}
  for i = 0, n do
    d[i + 1] = { [0] = n + m, [1] = i }
  end
  for j = 0, m do
    d[0][j + 1] = n + m
    d[1][j + 1] = j
  end
  for i = 1, n do
    local previous = 0
    for j = 1, m do
      local row, col = seen[rhs[j]] or 0, previous
      local cost = 1
      if lhs[i] == rhs[j] then
        cost = 0
        previous = j
      end
      d[i + 1][j + 1] =
        math.min(d[i][j] + cost, d[i + 1][j] + 1, d[i][j + 1] + 1, d[row][col] + (i - row - 1) + 1 + (j - col - 1))
    end
    seen[lhs[i]] = i
  end
  return d[n + 1][m + 1]
end

---@param lhs string
---@param rhs string
---@return integer
M.damerau_levenshtein = function(lhs, rhs)
  return damerau_levenshtein(chars(lhs), chars(rhs))
end

---@param look_ahead integer
---@param lhs string
---@param rhs string
---@return number
M.multi_set_ratio = function(look_ahead, lhs, rhs)
  return multiset(look_ahead, chars(lhs), chars(rhs))
end

---@param look_ahead integer
---@param lhs string
---@param rhs string
---@return number
M.quick_ratio = function(look_ahead, lhs, rhs)
  local l, r = chars(lhs), chars(rhs)
  local shorter = math.min(#l, #r)
  if shorter == 0 then
    return 1
  end
  local count = prefix(l, r)
  local ratio = count / shorter
  local lhs_remaining = vim.list_slice(l, count + 1)
  local rhs_remaining = vim.list_slice(r, count + 1)
  return ratio + multiset(look_ahead, lhs_remaining, rhs_remaining) * (1 - ratio) * 0.5
end

---@class match.Metrics
---@field prefix_matches integer
---@field edit_distance number

---@param look_ahead integer
---@param lhs string
---@param rhs string
---@return match.Metrics
M.metrics = function(look_ahead, lhs, rhs)
  local l, r = chars(lhs), chars(rhs)
  local shorter = math.min(#l, #r)
  if shorter == 0 then
    return { prefix_matches = 0, edit_distance = 0 }
  end
  local count = prefix(l, r)
  local cutoff = math.min(math.max(#l, #r), shorter + look_ahead)
  local lhs_remaining = vim.list_slice(l, count + 1, cutoff)
  local rhs_remaining = vim.list_slice(r, count + 1, cutoff)
  local dist = damerau_levenshtein(lhs_remaining, rhs_remaining)
  return { prefix_matches = count, edit_distance = 1 - (dist - (cutoff - shorter)) / shorter }
end

---@param look_ahead integer
---@param token string
---@param candidate string
---@return number score
M.score = function(look_ahead, token, candidate)
  if token == "" then
    return 0
  end
  if token == string.lower(token) then
    candidate = string.lower(candidate)
  end
  return M.quick_ratio(look_ahead, token, candidate)
end

return M
