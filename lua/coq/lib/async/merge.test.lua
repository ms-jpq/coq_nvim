local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"

local delayed = function(value, delay)
  local sent = false
  return function()
    if sent then
      return nil
    end
    async.sleep(delay)
    if async.current().cancelled then
      return nil
    end
    sent = true
    return value
  end
end

T.describe("merge", function(test)
  test("of one iter yields values until exhausted", function()
    local i = 0
    local iter = function()
      i = i + 1
      if i > 3 then
        return nil
      end
      async.sleep(2)
      return i * 10
    end

    local out = {}
    for _, v in async.merge { iter } do
      table.insert(out, v)
    end

    T.eq(out, { 10, 20, 30 })
  end)

  test("returns each iter's value in completion order", function()
    local out = {}
    for _, v in
      async.merge {
        delayed("a", 2),
        delayed("c", 6),
        delayed("b", 4),
      }
    do
      table.insert(out, v)
    end

    T.eq(out, { "a", "b", "c" })
  end)

  test("returns the original iter index alongside the value", function()
    local out = {}
    for idx, v in
      async.merge {
        delayed("a", 2),
        delayed("c", 6),
        delayed("b", 4),
      }
    do
      table.insert(out, { idx, v })
    end

    T.eq(out, { { 1, "a" }, { 3, "b" }, { 2, "c" } })
  end)

  test("returns nil when ambient handle cancelled mid-merge", function()
    local h = handle.new()
    local got
    async.scope(h, function(n)
      n.spawn(function()
        local iter = function()
          async.sleep(100)
          return "never"
        end
        got = async.merge { iter }()
      end)
      h.cancel()
    end)

    T.eq(got, nil)
  end)

  test("explicit handle short-circuits the merge", function()
    local sh = handle.new()
    local got
    async.scope(sh, function(n)
      n.spawn(function()
        local iter = function()
          async.sleep(100)
          return "never"
        end
        got = async.merge { iter }()
      end)
      sh.cancel()
    end)

    T.eq(got, nil)
  end)
end)
