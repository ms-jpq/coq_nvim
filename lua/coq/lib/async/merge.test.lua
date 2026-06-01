local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"

local delayed = function(value, delay)
  local sent = false
  return function()
    if sent then
      return nil
    end
    async.sleep(delay)
    if runtime.current().cancelled then
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
      async.sleep(2 * T.SLOW)
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
        delayed("a", 2 * T.SLOW),
        delayed("c", 6 * T.SLOW),
        delayed("b", 4 * T.SLOW),
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
        delayed("a", 2 * T.SLOW),
        delayed("c", 6 * T.SLOW),
        delayed("b", 4 * T.SLOW),
      }
    do
      table.insert(out, { idx, v })
    end

    T.eq(out, { { 1, "a" }, { 3, "b" }, { 2, "c" } })
  end)

  test("returns nil when ambient handle cancelled mid-merge", function()
    local nursery = require "coq.lib.async.nursery"
    local h = handle.new()
    local got
    local n = nursery.new(); local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      local iter = function()
        async.sleep(100 * T.SLOW)
        return "never"
      end
      got = async.merge { iter }()
    end)
    h.cancel()
    n.join()

    T.eq(got, nil)
  end)

  test("close stops further pulls", function()
    local m = async.merge {
      function()
        async.sleep(100 * T.SLOW)
        return "never"
      end,
    }
    m.close()

    T.eq(m(), nil)
  end)

  test("close raises errors from a failed iter", function()
    local m = async.merge {
      function()
        async.sleep(2 * T.SLOW)
        error("bad dog", 0)
      end,
    }

    async.sleep(50 * T.SLOW)
    local ok, err = pcall(m.close)
    T.eq(ok, false)
    T.eq(err, "bad dog")
  end)

  test("pull raises errors from a failed iter", function()
    local m = async.merge {
      function()
        async.sleep(2 * T.SLOW)
        error("bad dog", 0)
      end,
    }

    local ok, err = pcall(function()
      for _ in m do
      end
    end)
    T.eq(ok, false)
    T.eq(err, "bad dog")
  end)

  test("close cancels in-flight producers", function()
    local fired = false
    async.scope(function(n)
      n.spawn(function()
        local m = async.merge {
          function()
            local _ = runtime.current().on_cancel(function()
              fired = true
            end)
            async.sleep(100 * T.SLOW)
            return "never"
          end,
        }
        async.sleep(5 * T.SLOW)
        m.close()
      end)
    end)

    T.eq(fired, true)
  end)
end)
