---@alias index.Scored [index.Row, number, integer[]?]

local M = {}

-- https://github.com/neovim/neovim/blob/master/src/nvim/fuzzy.c
M.WEIGHTS = { prox = 100, recen = 50 }

---@param rows index.Row[]
---@param prepared index.Prepared
---@return lib.Iterator<index.Scored>
M.score = function(rows, prepared)
  local token = prepared.token

  local by_filter = (function()
    if token == "" then
      return vim.iter(rows):fold({}, function(acc, row)
        acc[row.filter] = { fuzzy = 0, positions = nil }
        return acc
      end)
    end

    local filters = vim
      .iter(rows)
      :map(function(row)
        return row.filter
      end)
      :totable()
    local matches, positions, scores = unpack(vim.fn.matchfuzzypos(filters, token))
    return vim.iter(matches):enumerate():fold({}, function(acc, i, f)
      acc[f] = { fuzzy = scores[i], positions = positions[i] }
      return acc
    end)
  end)()

  return vim
    .iter(rows)
    :filter(function(row)
      return by_filter[row.filter] ~= nil
    end)
    :map(function(row)
      local hit = by_filter[row.filter]
      local prox = prepared.locality[row.filter] or 0
      local recen = prepared.recency[row.filter] or 0
      local bias = prepared.source_bias[row.source] or 1

      return row, (hit.fuzzy + prox * M.WEIGHTS.prox + recen * M.WEIGHTS.recen) * bias, hit.positions
    end) --[[@as lib.Iterator<index.Scored>]]
end

return M
