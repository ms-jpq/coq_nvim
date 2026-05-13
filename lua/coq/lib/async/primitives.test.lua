local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("future cancel", function(test)
  test("await returns nil when ambient handle already cancelled", function()
    local h = async.handle()
    h.cancel()

    async.run(h, function()
      local _, await = async.future()

      T.eq(await(), nil)
    end)
  end)

  test("await with explicit handle returns nil when that handle cancelled", function()
    local h = async.handle()
    h.cancel()
    local _, await = async.future(h)

    T.eq(await(), nil)
  end)

  test("await returns resolved value when not cancelled", function()
    async.run(async.ROOT, function()
      local resolve, await = async.future()
      resolve "woof"

      T.eq(await(), "woof")
    end)
  end)

  test("await wakes with nil when cancelled mid-yield", function()
    local h = async.handle()
    local awoke = false
    local got
    async.run(h, function()
      local _, await = async.future()
      got = await()
      awoke = true
    end)
    h.cancel()

    T.eq(awoke, true)
    T.eq(got, nil)
  end)

  test("resolve after cancel is silent", function()
    local h = async.handle()
    local resolve
    async.run(h, function()
      local _resolve, await = async.future()
      resolve = _resolve
      await()
    end)
    h.cancel()
    local ok = pcall(resolve, "late")

    T.eq(ok, true)
  end)
end)

T.describe("sleep cancel", function(test)
  test("returns immediately when ambient handle already cancelled", function()
    local h = async.handle()
    h.cancel()

    async.run(h, function()
      local start = vim.uv.hrtime()
      async.sleep(100)
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

      assert(elapsed_ms < 20, ("expected immediate, got %.1fms"):format(elapsed_ms))
    end)
  end)

  test("returns early when cancelled mid-sleep", function()
    local h = async.handle()
    local elapsed_ms

    async.run(h, function()
      local start = vim.uv.hrtime()
      async.sleep(200)
      elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    end)

    async.sleep(10)
    h.cancel()
    async.sleep(20)

    assert(elapsed_ms and elapsed_ms < 60, ("expected ~10ms, got %s"):format(tostring(elapsed_ms)))
  end)
end)
