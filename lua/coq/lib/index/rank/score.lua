local atools = require "coq.lib.atools"

---@class index.Scorable
---@field filter string
---@field source string
---@field always_on_top? boolean

---@alias index.Scored [index.Scorable, number, integer[]?]

local M = {}

-- https://github.com/neovim/neovim/blob/master/src/nvim/fuzzy.c
M.WEIGHTS = { prox = 100, recen = 50 }
M.ALWAYS_TOP = 1e9

---@param items index.Scorable[]
---@param prepared index.Prepared
---@return lib.Iterator<index.Scored>
M.compute = function(items, prepared)
  atools.scheduled()

  local by_filter = (function()
    if prepared.token == "" then
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

    local matches, positions, scores = unpack(vim.fn.matchfuzzypos(filters, prepared.token))
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
      local tier = item.always_on_top and M.ALWAYS_TOP or 0

      local score = (hit.fuzzy + prox * M.WEIGHTS.prox + recen * M.WEIGHTS.recen) * bias + tier
      return item, score, hit.positions
    end) --[[@as lib.Iterator<index.Scored>]]
end

return M
