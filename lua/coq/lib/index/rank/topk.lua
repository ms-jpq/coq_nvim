local M = {}

local by_neg_score = function(x)
  return -x.score
end

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
    local n, i = #items, 0
    return function()
      i = i + 1
      if i > n then
        return nil
      end
      return items[i].row
    end
  end

  return topk
end

return M
