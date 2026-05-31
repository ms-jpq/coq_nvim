-- the heap is item-agnostic; tests push bare strings where completions.Item is expected.
---@diagnostic disable: param-type-mismatch
local T = require "coq.lib.test"
local topk = require "coq.lib.index.rank.topk"

T.describe("topk", function(test)
  test("empty heap yields no rows", function()
    local h = topk.new(3)
    T.eq(vim.iter(h.iter()):totable(), {})
  end)

  test("rows returned in descending score", function()
    local h = topk.new(3)
    h.push("labrador", 3)
    h.push("golden_retriever", 10)
    h.push("poodle", 5)

    T.eq(vim.iter(h.iter()):totable(), { "golden_retriever", "poodle", "labrador" })
  end)

  test("push beyond k drops the lowest score", function()
    local h = topk.new(3)
    h.push("golden_retriever", 10)
    h.push("labrador", 3)
    h.push("poodle", 5)
    h.push("boxer", 7)

    T.eq(vim.iter(h.iter()):totable(), { "golden_retriever", "boxer", "poodle" })
  end)

  test("push at or below the floor of a full heap is rejected", function()
    local h = topk.new(2)
    h.push("golden_retriever", 10)
    h.push("poodle", 5)
    h.push("labrador", 5) -- equal to floor: rejected
    h.push("boxer", 1) -- below floor: rejected

    T.eq(vim.iter(h.iter()):totable(), { "golden_retriever", "poodle" })
  end)

  test("ties resolve in insertion order", function()
    local h = topk.new(3)
    h.push("labrador", 5)
    h.push("poodle", 5)
    h.push("boxer", 5)

    T.eq(vim.iter(h.iter()):totable(), { "labrador", "poodle", "boxer" })
  end)

  test("k = 1 keeps only the single best", function()
    local h = topk.new(1)
    h.push("labrador", 3)
    h.push("golden_retriever", 10)
    h.push("poodle", 5)

    T.eq(vim.iter(h.iter()):totable(), { "golden_retriever" })
  end)
end)
