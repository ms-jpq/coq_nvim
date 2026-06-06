local atools = require "coq.lib.atools"
local default_dict = require "coq.lib.default_dict"
local itertools = require "coq.lib.itertools"
local tokens = require "coq.lib.index.tokens"

---@class index.Prepared
---@field token string
---@field locality table<string, integer>
---@field recency table<string, integer>
---@field source_bias table<string, number>
---@field weights config.Weights

---@class statsd.Recording
---@field tally fun(count: integer)
---@field done fun(interrupted: boolean)

---@class statsd.Sample
---@field duration number
---@field items integer
---@field interrupted boolean

---@class statsd.Summary
---@field interrupted integer
---@field inserted integer
---@field avg_duration number
---@field q10_duration number
---@field q50_duration number
---@field q95_duration number
---@field q99_duration number
---@field avg_items number
---@field q50_items number
---@field q99_items number

---@class index.Statsd
---@field inserted fun(item: completions.Item)
---@field prepare fun(ctx: ctx.full): index.Prepared
---@field record fun(source: string): statsd.Recording
---@field summary fun(): table<string, statsd.Summary>

local M = {}

M.ALWAYS_TOP = 1e9
M.WEIGHT_SCALE = 100

local SAMPLE_CAP = 200

---@param prepared index.Prepared
---@param item completions.Item
---@return number
M.score = function(prepared, item)
  local meta = item.meta
  local prox = prepared.locality[meta.filter] or 0
  local recen = prepared.recency[meta.filter] or 0
  local bias = prepared.source_bias[meta.source] or 1
  local tier = meta.always_on_top and M.ALWAYS_TOP or 0
  local w = prepared.weights

  return (meta.fuzzy + prox * w.proximity * M.WEIGHT_SCALE + recen * w.recency * M.WEIGHT_SCALE) * bias + tier
end

---@class statsd.Bucket
---@field samples statsd.Sample[]
---@field write integer
---@field count integer
---@field inserted integer

---@return statsd.Bucket
local new_bucket = function()
  return { samples = {}, write = 1, count = 0, inserted = 0 }
end

---@param bucket statsd.Bucket
---@param sample statsd.Sample
local push_sample = function(bucket, sample)
  bucket.samples[bucket.write] = sample
  bucket.write = (bucket.write % SAMPLE_CAP) + 1
  if bucket.count < SAMPLE_CAP then
    bucket.count = bucket.count + 1
  end
end

---@param sorted number[]
---@param p number
---@return number
local quantile = function(sorted, p)
  local n = #sorted
  if n == 0 then
    return 0
  end
  local idx = math.max(1, math.min(n, math.floor(p * (n - 1) + 1.5)))
  return sorted[idx]
end

---@param bucket statsd.Bucket
---@return statsd.Summary
local summarize = function(bucket)
  local durations, items = {}, {}
  local interrupted_count, sum_duration, sum_items = 0, 0, 0
  for i = 1, bucket.count do
    local s = bucket.samples[i]
    durations[i] = s.duration
    items[i] = s.items
    sum_duration = sum_duration + s.duration
    sum_items = sum_items + s.items
    if s.interrupted then
      interrupted_count = interrupted_count + 1
    end
  end
  table.sort(durations)
  table.sort(items)

  local n = math.max(1, bucket.count)
  return {
    interrupted = interrupted_count,
    inserted = bucket.inserted,
    avg_duration = sum_duration / n,
    q10_duration = quantile(durations, 0.10),
    q50_duration = quantile(durations, 0.50),
    q95_duration = quantile(durations, 0.95),
    q99_duration = quantile(durations, 0.99),
    avg_items = sum_items / n,
    q50_items = quantile(items, 0.50),
    q99_items = quantile(items, 0.99),
  }
end

---@param settings config.Settings
---@return index.Statsd
M.new = function(settings)
  local source_bias = {}
  for name, client in pairs(settings.clients) do
    source_bias[name] = 1 + (client.weight_adjust or 0)
  end

  ---@type lib.DefaultDict<string, statsd.Bucket>
  local buckets = default_dict.new(new_bucket)

  ---@type lib.DefaultDict<string, integer>
  local recency = default_dict.new(function()
    return 0
  end)

  ---@diagnostic disable-next-line: missing-fields
  local statsd = {} ---@type index.Statsd

  statsd.inserted = function(item)
    recency[item.meta.filter] = recency[item.meta.filter] + 1
    buckets[item.meta.source].inserted = buckets[item.meta.source].inserted + 1
  end

  statsd.prepare = function(ctx)
    atools.scheduled()
    return {
      token = ctx.keyword_before,
      locality = tokens.locality(
        ctx.iskeyword,
        itertools.intersperse(ctx.linesep, vim.iter(tokens.surround(ctx)) --[[@as lib.Iterator<string>]])
      ),
      recency = recency,
      source_bias = source_bias,
      weights = settings.weights,
    }
  end

  statsd.record = function(source)
    local t0 = vim.uv.hrtime()
    local items = 0

    ---@diagnostic disable-next-line: missing-fields
    local recorder = {} ---@type statsd.Recording

    recorder.tally = function(count)
      items = items + count
    end

    recorder.done = function(interrupted)
      local duration = (vim.uv.hrtime() - t0) / 1e9
      push_sample(buckets[source], {
        duration = duration,
        items = items,
        interrupted = interrupted,
      })
    end

    return recorder
  end

  statsd.summary = function()
    local out = {}
    for source, bucket in pairs(buckets) do
      out[source] = summarize(bucket)
    end
    return out
  end

  return statsd
end

return M
