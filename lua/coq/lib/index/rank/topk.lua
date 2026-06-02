---@class index.TopK<T>
---@field push fun(item: T, score: number)
---@field iter fun(): lib.Iterator<T>

local M = {}

---@generic T
---@param k integer
---@param key_fn? fun(item: T): any
---@return index.TopK<T>
M.new = function(k, key_fn)
  assert(k > 0)
  local entries = {}
  local by_key = {}

  local topk = {}

  topk.push = function(item, score)
    local key = key_fn and key_fn(item)
    if key ~= nil then
      local idx = by_key[key]
      if idx then
        local prev = entries[idx]
        if score > prev.score then
          entries[idx] = { score = score, item = item, seq = prev.seq }
        end
        return
      end
    end
    local seq = #entries + 1
    entries[seq] = { score = score, item = item, seq = seq }
    if key ~= nil then
      by_key[key] = seq
    end
  end

  topk.iter = function()
    local sorted = vim.list_slice(entries)
    table.sort(sorted, function(a, b)
      if a.score ~= b.score then
        return a.score > b.score
      end
      return a.seq < b.seq
    end)
    return vim.iter(sorted):take(k):map(function(e)
      return e.item
    end)
  end

  return topk
end

return M
