local T = require "coq.lib.test"
local statsd = require "coq.lib.index.rank.statsd"

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

---@param overrides? table
---@return index.Prepared
local prep = function(overrides)
  local p = { token = "", locality = {}, recency = {}, source_bias = {} }
  for k, v in pairs(overrides or {}) do
    p[k] = v
  end
  return p
end

local fido = function(extra)
  return item(vim.tbl_extend("force", { filter = "fido", source = "BF", fuzzy = 0 }, extra or {}))
end

T.describe("rank.score", function(test)
  test("with no signals the score is the fuzzy score", function()
    T.eq(statsd.score(prep(), fido { fuzzy = 7 }), 7)
  end)

  test("proximity adds prox * WEIGHTS.prox", function()
    local base = statsd.score(prep(), fido())
    local boosted = statsd.score(prep { locality = { fido = 2 } }, fido())
    T.eq(boosted - base, 2 * statsd.WEIGHTS.prox)
  end)

  test("recency adds recen * WEIGHTS.recen", function()
    T.eq(statsd.score(prep { recency = { fido = 3 } }, fido()), 3 * statsd.WEIGHTS.recen)
  end)

  test("source bias multiplies the score", function()
    T.eq(statsd.score(prep { source_bias = { BF = 2 } }, fido { fuzzy = 5 }), 10)
  end)

  test("source bias defaults to 1 when the source is absent", function()
    T.eq(statsd.score(prep { source_bias = { other = 9 } }, fido { fuzzy = 5 }), 5)
  end)

  test("always_on_top adds the ALWAYS_TOP tier last (after bias)", function()
    T.eq(
      statsd.score(prep { source_bias = { BF = 2 } }, fido { fuzzy = 1, always_on_top = true }),
      2 + statsd.ALWAYS_TOP
    )
  end)

  test("combines (fuzzy + prox + recen) * bias + tier", function()
    local p = prep { locality = { fido = 2 }, recency = { fido = 1 }, source_bias = { BF = 2 } }
    local expected = (3 + 2 * statsd.WEIGHTS.prox + 1 * statsd.WEIGHTS.recen) * 2 + statsd.ALWAYS_TOP
    T.eq(statsd.score(p, fido { fuzzy = 3, always_on_top = true }), expected)
  end)
end)
