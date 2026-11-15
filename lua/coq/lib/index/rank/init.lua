local item_m = require "coq.completions.item"
local measure = require "coq.lib.index.rank.measure"

local M = {}

local FEATURES = { "prefix_matches", "edit_distance", "recency", "proximity" }

local rounded = function(value)
  local floor = math.floor(value)
  local rest = value - floor
  return (rest > 0.5 or (rest == 0.5 and floor % 2 ~= 0)) and floor + 1 or floor
end

local swapcase_char = function(c)
  return c == string.lower(c) and string.upper(c) or string.lower(c)
end

local swapcase = function(text)
  return (string.gsub(text, "%a", swapcase_char))
end

---@param settings config.Settings
---@param history table<string, integer>
---@param ctx ctx.full
---@return rank.Ranker
M.new = function(settings, history, ctx)
  local source_bias = {}
  for name, client in pairs(settings.clients) do
    local adjustment = client.weight_adjust or 0
    source_bias[name] = 1 + adjustment / (1 + math.abs(adjustment)) / 2
  end
  local entries = {}
  local totals = { prefix_matches = 0, edit_distance = 0, recency = 0, proximity = 0 }
  ---@param items rank.Measured[]
  local add = function(items)
    for _, measured in ipairs(items) do
      local metrics = vim.tbl_extend("force", measured.metrics, { recency = history[measured.item.meta.filter] or 0 })
      for key, value in pairs(metrics) do
        totals[key] = totals[key] + value
      end
      table.insert(entries, { item = measured.item, metrics = metrics, index = #entries + 1 })
    end
  end

  ---@param limit integer
  ---@return completions.Item[]
  local rank = function(limit)
    assert(limit > 0)
    local divisors = {}
    for _, key in ipairs(FEATURES) do
      local weight = settings.weights[key] or 0
      divisors[key] = weight ~= 0 and totals[key] / weight or 0
    end
    for _, entry in ipairs(entries) do
      local item = entry.item
      local meta = item.meta
      local score = 0
      for _, key in ipairs(FEATURES) do
        local value = entry.metrics[key]
        local divisor = divisors[key]
        if divisor ~= 0 then
          score = score + value / divisor
        end
      end
      local lsp = meta.lsp and meta.lsp.item
      entry.key = {
        lsp and lsp.preselect and -1 or 0,
        meta.always_on_top and -1 or 0,
        -rounded(score * (source_bias[meta.source] or 1) * 10000),
        -(lsp and lsp.additionalTextEdits and #lsp.additionalTextEdits or 0),
        meta.lsp and -1 or 0,
        item.kind and item.kind ~= "" and -1 or 0,
        (meta.doc ~= nil or (lsp and lsp.documentation ~= nil)) and -1 or 0,
        string.find(string.sub(meta.filter, 1, 1), "%w") and -1 or 0,
        not ctx.keyword_before_has_upper and swapcase(meta.filter) or meta.filter,
      }
    end

    local ordered = vim.list_slice(entries)
    table.sort(ordered, function(a, b)
      for i, value in ipairs(a.key) do
        if value ~= b.key[i] then
          return value < b.key[i]
        end
      end
      return a.index < b.index
    end)

    local seen, ranked = {}, {}
    for _, entry in ipairs(ordered) do
      local key = item_m.dedup_key(entry.item)
      if not seen[key] then
        seen[key] = true
        table.insert(ranked, entry.item)
        if #ranked >= limit then
          break
        end
      end
    end
    return ranked
  end
  return { add = add, rank = rank }
end

---@class rank.Ranker
---@field add fun(items: rank.Measured[])
---@field rank fun(limit: integer): completions.Item[]

---@param settings config.Settings
---@param history table<string, integer>
---@param ctx ctx.full
---@param items completions.Item[]
---@param limit integer
---@return completions.Item[]
M.rank = function(settings, history, ctx, items, limit)
  local ranker = M.new(settings, history, ctx)
  ranker.add(measure.batch(settings, ctx, items))
  return ranker.rank(limit)
end

return M
