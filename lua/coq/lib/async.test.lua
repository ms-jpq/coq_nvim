local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("async", function(test)
  test("future resolves synchronously", function()
    local resolve, await = async.future()
    resolve "woof"

    T.eq(await(), "woof")
  end)

  test("wrap returns callback args", function()
    local bark = async.wrap(function(name, cb)
      cb(name .. ":woof")
    end)

    T.eq(bark "rex", "rex:woof")
  end)

  test("wrap forwards multiple callback values", function()
    local pack = async.wrap(function(cb)
      cb("rex", "spot", "fido")
    end)
    local a, b, c = pack()

    T.eq({ a, b, c }, { "rex", "spot", "fido" })
  end)

  test("thunk defers execution", function()
    local ran = false
    local later = async(function()
      ran = true
    end)

    T.eq(ran, false)
    later()
    T.eq(ran, true)
  end)

  test("run propagates errors", function()
    local ok = pcall(function()
      async.run(function()
        error "rex went missing"
      end)
    end)

    T.eq(ok, false)
  end)

  test("sleep yields for the requested duration", function()
    local start = vim.uv.hrtime()
    async.sleep(20)
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert(elapsed_ms >= 15, ("expected ~20ms, got %.1fms"):format(elapsed_ms))
  end)
end)

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

T.describe("select", function(test)
  test("returns winning tag and value on sync resolve", function()
    local tag, val = async.select {
      function(resolve)
        resolve "woof"
      end,
      "rex",
    }

    T.eq(tag, "rex")
    T.eq(val, "woof")
  end)

  test("picks first entry on simultaneous sync resolve", function()
    local tag, val = async.select({
      function(resolve)
        resolve "first"
      end,
      1,
    }, {
      function(resolve)
        resolve "second"
      end,
      2,
    })

    T.eq(tag, 1)
    T.eq(val, "first")
  end)

  test("picks fastest async resolver", function()
    local tag, val = async.select(
      { after(30, "slow"), "slow" },
      { after(5, "fast"), "fast" },
      { after(60, "slowest"), "slowest" }
    )

    T.eq(tag, "fast")
    T.eq(val, "fast")
  end)

  test("forwards multiple values", function()
    local tag, a, b, c = async.select {
      function(resolve)
        resolve("rex", "fido", "spot")
      end,
      1,
    }

    T.eq(tag, 1)
    T.eq({ a, b, c }, { "rex", "fido", "spot" })
  end)

  test("ignores late resolves", function()
    local stashed
    local tag, val = async.select({
      function(resolve)
        resolve "winner"
      end,
      1,
    }, {
      function(resolve)
        stashed = resolve
      end,
      2,
    })

    T.eq(tag, 1)
    T.eq(val, "winner")

    stashed "loser"
    async.sleep(5)
    T.eq(tag, 1)
    T.eq(val, "winner")
  end)

  test("tag can be any value", function()
    local sentinel = { breed = "shiba" }
    local tag = async.select { after(5, "ok"), sentinel }

    T.eq(tag, sentinel)
  end)

  test("sync entry beats later async entries", function()
    local async_ran = false
    local tag = async.select({
      function(resolve)
        resolve()
      end,
      "sync",
    }, {
      function(resolve)
        async_ran = true
        vim.uv.new_timer():start(5, 0, function()
          resolve()
        end)
      end,
      "async",
    })

    T.eq(tag, "sync")
    T.eq(async_ran, true)
  end)
end)
