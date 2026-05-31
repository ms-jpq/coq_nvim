local T = require "coq.lib.test"
local score = require "coq.lib.index.rank.score"

local mk = function(filter, source)
  return { filter = filter, source = source or "buffer" }
end

local prep = function(token, overrides)
  local p = {
    token = token,
    locality = {},
    recency = {},
    source_bias = {},
  }
  for k, v in pairs(overrides or {}) do
    p[k] = v
  end
  return p
end

local collect = function(iter)
  local out = {}
  for row, s in iter do
    table.insert(out, { row = row, score = s })
  end
  return out
end

local one = function(filter, p)
  return collect(score.compute({ mk(filter) }, p))[1]
end

T.describe("score", function(test)
  test("non-matching filter is dropped from the output", function()
    T.eq(collect(score.compute({ mk "golden_retriever" }, prep "xyz")), {})
  end)

  test("matching filter survives with a positive score", function()
    local s = one("golden_retriever", prep "gold")
    assert(s and s.score > 0, "expected positive number, got " .. vim.inspect(s))
  end)

  test("empty token passes every row with fuzzy = 0", function()
    local s = one("golden_retriever", prep "")
    T.eq(s.score, 0)
  end)

  test("empty token still applies proximity / recency / bias", function()
    local p = prep("", {
      locality = { golden_retriever = 2 },
      recency = { golden_retriever = 1 },
      source_bias = { buffer = 2 },
    })
    T.eq(one("golden_retriever", p).score, (2 * score.WEIGHTS.prox + 1 * score.WEIGHTS.recen) * 2)
  end)

  test("proximity adds to the score", function()
    local plain = one("golden_retriever", prep "gold").score
    local boosted = one("golden_retriever", prep("gold", { locality = { golden_retriever = 1 } })).score
    T.eq(boosted - plain, score.WEIGHTS.prox)
  end)

  test("recency adds to the score", function()
    local plain = one("golden_retriever", prep "gold").score
    local boosted = one("golden_retriever", prep("gold", { recency = { golden_retriever = 5 } })).score
    T.eq(boosted - plain, 5 * score.WEIGHTS.recen)
  end)

  test("source bias multiplies the score", function()
    local plain = one("golden_retriever", prep "gold").score
    local boosted = one("golden_retriever", prep("gold", { source_bias = { buffer = 2 } })).score
    T.eq(boosted, plain * 2)
  end)

  test("default source bias is 1 (neutral) when source absent from table", function()
    local missing =
      collect(score.compute({ mk("golden_retriever", "lsp") }, prep("gold", { source_bias = { buffer = 2 } })))[1].score
    local plain = one("golden_retriever", prep "gold").score
    T.eq(missing, plain)
  end)

  test("survivors come back in input order", function()
    -- "ld" matches golden_retriever and labrador; poodle has no l-then-d
    local rows = { mk "golden_retriever", mk "poodle", mk "labrador" }
    local out = collect(score.compute(rows, prep "ld"))
    local filters = {}
    for _, s in ipairs(out) do
      table.insert(filters, s.row.filter)
    end
    T.eq(filters, { "golden_retriever", "labrador" })
  end)

  test("rows sharing a filter both receive the same fuzzy score", function()
    local rows = { mk("golden_retriever", "buffer"), mk("golden_retriever", "lsp") }
    local out = collect(score.compute(rows, prep "gold"))
    T.eq(#out, 2)
    T.eq(out[1].score, out[2].score)
  end)

  test("non-matchers are excluded, matchers retained", function()
    local rows = { mk "golden_retriever", mk "xyzzy", mk "labrador" }
    local out = collect(score.compute(rows, prep "lab"))
    T.eq(#out, 1)
    T.eq(out[1].row.filter, "labrador")
  end)
end)
