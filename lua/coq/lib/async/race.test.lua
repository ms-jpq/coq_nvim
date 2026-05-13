local T = require "coq.lib.test"
local async = require "coq.lib.async"

local after = function(ms, ...)
  local args = { ... }
  return function(resolve)
    local timer = vim.uv.new_timer()
    timer:start(ms, 0, function()
      timer:stop()
      timer:close()
      resolve(unpack(args))
    end)
  end
end

T.describe("race", function(test)
  test("returns winning idx and value on sync resolve", function()
    local idx, val = async.race {
      function(resolve)
        resolve "woof"
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "woof")
  end)

  test("picks first future on simultaneous sync resolve", function()
    local idx, val = async.race {
      function(resolve)
        resolve "first"
      end,
      function(resolve)
        resolve "second"
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "first")
  end)

  test("picks fastest async resolver", function()
    local idx, val = async.race {
      after(30, "slow"),
      after(5, "fast"),
      after(60, "slowest"),
    }

    T.eq(idx, 2)
    T.eq(val, "fast")
  end)

  test("forwards multiple values", function()
    local idx, a, b, c = async.race {
      function(resolve)
        resolve("lil", "fido", "spot")
      end,
    }

    T.eq(idx, 1)
    T.eq({ a, b, c }, { "lil", "fido", "spot" })
  end)

  test("ignores late resolves", function()
    local stashed
    local idx, val = async.race {
      function(resolve)
        resolve "winner"
      end,
      function(resolve)
        stashed = resolve
      end,
    }

    T.eq(idx, 1)
    T.eq(val, "winner")

    stashed "loser"
    async.sleep(5)
    T.eq(idx, 1)
    T.eq(val, "winner")
  end)

  test("sync entry beats later async entries", function()
    local async_ran = false
    local idx = async.race {
      function(resolve)
        resolve()
      end,
      function(resolve)
        async_ran = true
        vim.uv.new_timer():start(5, 0, function()
          resolve()
        end)
      end,
    }

    T.eq(idx, 1)
    T.eq(async_ran, true)
  end)
end)
