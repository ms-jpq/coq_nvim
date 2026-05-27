---@alias index.Scored [completions.Item, number, integer[]?]

local M = {}

-- https://github.com/neovim/neovim/blob/master/src/nvim/fuzzy.c
M.WEIGHTS = { prox = 100, recen = 50 }

---@param items completions.Item[]
---@param prepared index.Prepared
---@return lib.Iterator<index.Scored>
M.score = function(items, prepared)
  local token = prepared.token

  local by_filter = (function()
    if token == "" then
      return vim.iter(items):fold({}, function(acc, item)
        acc[item.filter] = { fuzzy = 0, positions = nil }
        return acc
      end)
    end

    local filters = vim
      .iter(items)
      :map(function(item)
        return item.filter
      end)
      :totable()
    local matches, positions, scores = unpack(vim.fn.matchfuzzypos(filters, token))
    return vim.iter(matches):enumerate():fold({}, function(acc, i, f)
      acc[f] = { fuzzy = scores[i], positions = positions[i] }
      return acc
    end)
  end)()

  return vim
    .iter(items)
    :filter(function(item)
      return by_filter[item.filter] ~= nil
    end)
    :map(function(item)
      local hit = by_filter[item.filter]
      local prox = prepared.locality[item.filter] or 0
      local recen = prepared.recency[item.filter] or 0
      local bias = prepared.source_bias[item.source] or 1

      return item, (hit.fuzzy + prox * M.WEIGHTS.prox + recen * M.WEIGHTS.recen) * bias, hit.positions
    end) --[[@as lib.Iterator<index.Scored>]]
end

return M
