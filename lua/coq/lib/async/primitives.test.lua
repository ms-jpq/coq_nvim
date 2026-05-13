local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("future cancel", function(test)
  test("await returns nil when ambient handle already cancelled", function()
    local h = async.handle()
    h.cancel()

    async.scope(h, function(n)
      n.spawn(function()
        local _, await = async.future()

        T.eq(await(), nil)
      end)
    end)
  end)

  test("await with explicit handle returns nil when that handle cancelled", function()
    local h = async.handle()
    h.cancel()
    local resolve, await = async.future()
    resolve(2)

    T.eq(await(h), nil)
  end)

  test("await returns resolved value when not cancelled", function()
    local resolve, await = async.future()
    resolve "woof"

    T.eq(await(), "woof")
  end)

  test("await wakes with nil when cancelled mid-yield", function()
    local h = async.handle()
    local awoke = false
    local got
    async.scope(h, function(n)
      n.spawn(function()
        local _, await = async.future()
        got = await()
        awoke = true
      end)
      h.cancel()
    end)

    T.eq(awoke, true)
    T.eq(got, nil)
  end)

  test("resolve after cancel is silent", function()
    local h = async.handle()
    local resolve
    async.scope(h, function(n)
      n.spawn(function()
        local _resolve, await = async.future()
        resolve = _resolve
        await()
      end)
      h.cancel()
    end)
    local ok = pcall(resolve, "late")

    T.eq(ok, true)
  end)
end)

T.describe("sleep cancel", function(test)
  test("returns immediately when ambient handle already cancelled", function()
    local h = async.handle()
    h.cancel()

    async.scope(h, function(n)
      n.spawn(function()
        local start = vim.uv.hrtime()
        async.sleep(100)
        local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

        assert(elapsed_ms < 20, ("expected immediate, got %.1fms"):format(elapsed_ms))
      end)
    end)
  end)

  test("returns early when cancelled mid-sleep", function()
    local h = async.handle()
    local elapsed_ms

    async.scope(h, function(n)
      n.spawn(function()
        local start = vim.uv.hrtime()
        async.sleep(200)
        elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      end)
      async.sleep(10)
      h.cancel()
    end)

    assert(elapsed_ms and elapsed_ms < 60, ("expected ~10ms, got %s"):format(tostring(elapsed_ms)))
  end)
end)
