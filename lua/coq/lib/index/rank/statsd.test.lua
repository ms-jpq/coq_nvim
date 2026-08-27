local T = require "coq.lib.test"
local statsd = require "coq.lib.index.rank.statsd"

local DEFAULT_ISKEYWORD = "@,48-57,_,192-255"

---@param meta { filter: string, source: string, fuzzy: integer, always_on_top: boolean? }
---@return completions.Item
local item = function(meta)
  return {
    word = meta.filter,
    meta = {
      uid = "uid",
      filter = meta.filter,
      source = meta.source,
      fuzzy = meta.fuzzy,
      always_on_top = meta.always_on_top,
    },
  } --[[@as completions.Item]]
end

local WEIGHTS = { proximity = 1.0, recency = 0.5 }

---@param overrides? table
---@return index.Prepared
local prep = function(overrides)
  local p = { token = "", locality = {}, recency = {}, source_bias = {}, weights = WEIGHTS }
  for k, v in pairs(overrides or {}) do
    p[k] = v
  end
  return p
end

local fido = function(extra)
  return item(vim.tbl_extend("force", { filter = "fido", source = "BF", fuzzy = 0 }, extra or {}))
end

---@return index.Statsd
local fresh = function()
  ---@diagnostic disable-next-line: missing-fields
  return statsd.new { clients = {}, weights = WEIGHTS }
end

T.describe({ "rank.score" }, function(test)
  test({ "with no signals the score is the fuzzy score" }, function()
    T.eq(statsd.score(prep(), fido { fuzzy = 7 }), 7)
  end)

  test({ "proximity multiplies the locality count by weights.proximity * WEIGHT_SCALE" }, function()
    local base = statsd.score(prep(), fido())
    local boosted = statsd.score(prep { locality = { fido = 2 } }, fido())
    T.eq(boosted - base, 2 * WEIGHTS.proximity * statsd.WEIGHT_SCALE)
  end)

  test({ "recency multiplies the recency count by weights.recency * WEIGHT_SCALE" }, function()
    T.eq(statsd.score(prep { recency = { fido = 3 } }, fido()), 3 * WEIGHTS.recency * statsd.WEIGHT_SCALE)
  end)

  test({ "custom weights override the multipliers" }, function()
    local p = prep { locality = { fido = 1 }, recency = { fido = 1 }, weights = { proximity = 3, recency = 5 } }
    T.eq(statsd.score(p, fido()), (3 + 5) * statsd.WEIGHT_SCALE)
  end)

  test({ "source bias multiplies the score" }, function()
    T.eq(statsd.score(prep { source_bias = { BF = 2 } }, fido { fuzzy = 5 }), 10)
  end)

  test({ "source bias defaults to 1 when the source is absent" }, function()
    T.eq(statsd.score(prep { source_bias = { other = 9 } }, fido { fuzzy = 5 }), 5)
  end)

  test({ "always_on_top adds the ALWAYS_TOP tier last (after bias)" }, function()
    T.eq(
      statsd.score(prep { source_bias = { BF = 2 } }, fido { fuzzy = 1, always_on_top = true }),
      2 + statsd.ALWAYS_TOP
    )
  end)

  test({ "combines (fuzzy + prox + recen) * bias + tier" }, function()
    local p = prep { locality = { fido = 2 }, recency = { fido = 1 }, source_bias = { BF = 2 } }
    local expected = (3 + (2 * WEIGHTS.proximity + 1 * WEIGHTS.recency) * statsd.WEIGHT_SCALE) * 2 + statsd.ALWAYS_TOP
    T.eq(statsd.score(p, fido { fuzzy = 3, always_on_top = true }), expected)
  end)
end)

T.describe({ "rank.statsd.inserted" }, function(test)
  test({ "inserted(item) bumps recency keyed by filter" }, function()
    local s = fresh()
    s.inserted(fido())
    s.inserted(fido())
    -- recency is internal, but observable through summary().inserted under the source bucket
    -- and through the prepare() output's recency map.
    T.eq(
      ---@diagnostic disable-next-line: missing-fields
      s.prepare({
        iskeyword = DEFAULT_ISKEYWORD,
        keyword_before = "",
        buf = 0,
        linesep = "\n",
      } --[[@as ctx.full]]).recency.fido,
      2
    )
  end)

  test({ "inserted(item) bumps the per-source inserted counter" }, function()
    local s = fresh()
    s.inserted(fido())
    s.inserted(fido())
    s.inserted(fido { source = "LS" })
    T.eq(s.summary().BF.inserted, 2)
    T.eq(s.summary().LS.inserted, 1)
  end)

  test({ "recency evicts the least recently used filter" }, function()
    local s = fresh()
    s.inserted(fido { filter = "old" })

    for i = 1, statsd.RECENCY_CAP do
      s.inserted(fido { filter = "new_" .. i })
    end

    ---@diagnostic disable-next-line: missing-fields
    local recency = s.prepare({
      iskeyword = DEFAULT_ISKEYWORD,
      keyword_before = "",
      buf = 0,
      linesep = "\n",
    } --[[@as ctx.full]]).recency

    T.eq(recency.old, nil)
    T.eq(recency.new_1, 1)
    T.eq(recency["new_" .. statsd.RECENCY_CAP], 1)
  end)
end)

T.describe({ "rank.statsd.record" }, function(test)
  test({ "record.tally + done writes a sample whose items match the tally sum" }, function()
    local s = fresh()
    local rec = s.record "BF"
    rec.tally(3)
    rec.tally(5)
    rec.done(false)
    local sum = s.summary().BF
    T.eq(sum.avg_items, 8)
    T.eq(sum.interrupted, 0)
  end)

  test({ "done(true) marks the sample interrupted" }, function()
    local s = fresh()
    local rec = s.record "BF"
    rec.tally(1)
    rec.done(true)
    T.eq(s.summary().BF.interrupted, 1)
  end)

  test({ "multiple records compose quantiles over items" }, function()
    local s = fresh()
    for _, n in pairs { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 } do
      local rec = s.record "BF"
      rec.tally(n)
      rec.done(false)
    end
    local sum = s.summary().BF
    T.eq(sum.avg_items, 55)
    -- Q50 of 1..10 mapped *10 → ~50–60 range depending on quantile rounding.
    assert(sum.q50_items >= 50 and sum.q50_items <= 60, "Q50 should be midband")
    assert(sum.q99_items >= 90, "Q99 should be near the top")
  end)

  test({ "summary() of an unseen source is absent" }, function()
    local s = fresh()
    T.eq(s.summary().nobody, nil)
  end)
end)
