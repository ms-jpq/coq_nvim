local M = {}

M.score = function(rows, prepared)
  local token = prepared.token

  local by_filter = {}
  if token == "" then
    for _, row in ipairs(rows) do
      by_filter[row.filter] = { fuzzy = 0, positions = nil }
    end
  else
    local seen = {}
    local filters = vim
      .iter(rows)
      :map(function(row)
        if seen[row.filter] then
          return nil
        end
        seen[row.filter] = true
        return row.filter
      end)
      :totable()
    local matches, positions, scores = unpack(vim.fn.matchfuzzypos(filters, token))
    for i, f in ipairs(matches) do
      by_filter[f] = { fuzzy = scores[i], positions = positions[i] }
    end
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
