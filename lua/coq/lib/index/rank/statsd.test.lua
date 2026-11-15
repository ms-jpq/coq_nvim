local T = require "coq.lib.test"
local statsd = require "coq.lib.index.rank.statsd"

---@param meta { filter: string, source: string, fuzzy: integer, always_on_top: boolean? }
---@return completions.Item
local item = function(meta)
  return {
    word = meta.filter,
    meta = {
      uid = "uid",
      filter = { meta.filter },
      source = meta.source,
      fuzzy = meta.fuzzy,
      always_on_top = meta.always_on_top,
    },
  } --[[@as completions.Item]]
end

local fido = function(extra)
  return item(vim.tbl_extend("force", { filter = "fido", source = "BF", fuzzy = 0 }, extra or {}))
end

---@return index.Statsd
local fresh = function()
  return statsd.new()
end

T.describe({ "rank.statsd.inserted" }, function(test)
  test({ "history records acceptance order and returned snapshots stay fixed" }, function()
    local s = fresh()
    s.inserted(fido())
    s.inserted(fido())
    local before = s.history()
    s.inserted(fido { filter = "rex" })
    local after = s.history()
    T.eq(before, { fido = 2 })
    T.eq(after, { fido = 2, rex = 3 })
  end)

  test({ "inserted(item) bumps recency keyed by filter" }, function()
    local s = fresh()
    s.inserted(fido())
    s.inserted(fido())
    T.eq(s.history().fido, 2)
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

    local recency = s.history()

    T.eq(recency.old, nil)
    T.eq(recency.new_1, 2)
    T.eq(recency["new_" .. statsd.RECENCY_CAP], statsd.RECENCY_CAP + 1)
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
