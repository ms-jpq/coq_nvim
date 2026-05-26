local M = {}

M.score = function(rows, prepared)
  local token = prepared.token

  if token == "" then
    local i = 0
    return function()
      i = i + 1
      local row = rows[i]
      if row == nil then
        return nil
      end
      local prox = prepared.locality[row.filter] or 0
      local rec = prepared.recency[row.filter] or 0
      local bias = prepared.source_bias[row.source] or 1
      return row, (3 * prox + rec) * bias, nil
    end
  end

  local filters, seen = {}, {}
  for _, row in ipairs(rows) do
    if not seen[row.filter] then
      seen[row.filter] = true
      table.insert(filters, row.filter)
    end
  end

  local matches, positions, scores = unpack(vim.fn.matchfuzzypos(filters, token))

  local by_filter = {}
  for i, f in ipairs(matches) do
    by_filter[f] = { fuzzy = scores[i], positions = positions[i] }
  end

  local i = 0
  return function()
    while true do
      i = i + 1
      local row = rows[i]
      if row == nil then
        return nil
      end
      local hit = by_filter[row.filter]
      if hit then
        local prox = prepared.locality[row.filter] or 0
        local rec = prepared.recency[row.filter] or 0
        local bias = prepared.source_bias[row.source] or 1
        return row, (hit.fuzzy + 3 * prox + rec) * bias, hit.positions
      end
    end
  end
end

return M
