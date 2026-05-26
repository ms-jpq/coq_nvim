local M = {}

-- transform: fuzzy subsequence match. Higher is better; nil drops the row.
-- Boundary / contiguous-run / exact-case bonuses. Per-row independent so the
-- streaming top-k stays correct before all sources finish.
M.match = function(token, filter)
  if token == "" then
    return 0
  end

  local hn, nn = #filter, #token
  local ni, run, score = 1, 0, 0

  for hi = 1, hn do
    if ni > nn then
      break
    end
    local hc = filter:sub(hi, hi)
    local nc = token:sub(ni, ni)
    if hc:lower() == nc:lower() then
      local prev = hi > 1 and filter:sub(hi - 1, hi - 1) or ""
      local boundary = hi == 1
        or prev == "_"
        or prev == "."
        or prev == "/"
        or prev == "-"
        or (prev:match "%l" ~= nil and hc:match "%u" ~= nil)

      run = run + 1
      score = score + run
      if boundary then
        score = score + 3
      end
      if hc == nc then
        score = score + 1
      end
      ni = ni + 1
    else
      run = 0
    end
  end

  if ni <= nn then
    return nil
  end

  return score - hn * 0.01 -- tie-break toward tighter matches
end

-- transform: proximity weight from the locality multiset
M.proximity = function(filter, locality)
  return locality[filter] or 0
end

-- transform: recency weight from a `filter -> count` insertion-history map
M.recency = function(filter, recency)
  return recency[filter] or 0
end

-- transform: per-source multiplier; defaults to 1 (neutral)
M.source_prior = function(source, priors)
  return priors[source] or 1
end

-- transform: composed per-row score. nil drops the row. Blend weights are
-- placeholders -- tune once real data flows through. Per-row independent given
-- `prepared`, so the streaming top-k is valid at every push.
M.score = function(row, prepared)
  local m = M.match(prepared.token, row.filter)
  if m == nil then
    return nil
  end
  local prox = M.proximity(row.filter, prepared.locality)
  local rec = M.recency(row.filter, prepared.recency)
  local prior = M.source_prior(row.source, prepared.priors)
  return (m + 3 * prox + rec) * prior
end

-- stateful: bounded sorted top-k, fed as rows arrive from the merged stream.
M.topk = function(k)
  assert(k > 0)
  local items = {}

  local topk = {}

  topk.push = function(row, score)
    if #items >= k and score <= items[#items].score then
      return
    end
    local i = 1
    while i <= #items and items[i].score >= score do
      i = i + 1
    end
    table.insert(items, i, { score = score, row = row })
    if #items > k then
      table.remove(items)
    end
  end

  topk.rows = function()
    local r = {}
    for i = 1, #items do
      r[i] = items[i].row
    end
    return r
  end

  return topk
end

return M
