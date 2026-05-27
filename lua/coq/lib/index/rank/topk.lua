---@class index.TopK
---@field push fun(row: index.Row, score: number)
---@field iter fun(): lib.Iterator<index.Row>

local M = {}

local by_neg_score = function(x)
  return -x.score
end

---@param k integer
---@return index.TopK
M.new = function(k)
  assert(k > 0)
  local items = {}

  local topk = {}

  topk.push = function(row, score)
    if #items >= k and score <= items[#items].score then
      return
    end

    local entry = { score = score, row = row }
    local i = vim.list.bisect(items, entry, { key = by_neg_score, bound = "upper" })

    table.insert(items, i, entry)

    if #items > k then
      table.remove(items)
    end
  end

  topk.iter = function()
    return vim.iter(items):map(function(entry)
      return entry.row
    end)
  end

  ---@cast topk index.TopK
  return topk
end

return M
