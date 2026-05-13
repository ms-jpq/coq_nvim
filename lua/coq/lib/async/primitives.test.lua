local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.cancel"

T.describe("future cancel", function(test)
  test("await returns nil when ambient token already cancelled", function()
    local token = cancel.token()
    token.cancel()

    async.run(token, function()
      local _, await = async.future()
      T.eq(await(), nil)
    end)
  end)

  test("await with explicit token returns nil when that token cancelled", function()
    local token = cancel.token()
    token.cancel()

    local _, await = async.future(token)
    T.eq(await(), nil)
  end)

  test("await returns resolved value when not cancelled", function()
    async.run(cancel.ROOT, function()
      local resolve, await = async.future()
      resolve "woof"
      T.eq(await(), "woof")
    end)
  end)
end)

T.describe("sleep cancel", function(test)
  test("returns immediately when ambient token already cancelled", function()
    local token = cancel.token()
    token.cancel()

    async.run(token, function()
      local start = vim.uv.hrtime()
      async.sleep(100)
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      assert(elapsed_ms < 20, ("expected immediate, got %.1fms"):format(elapsed_ms))
    end)
  end)

  test("returns early when cancelled mid-sleep", function()
    local token = cancel.token()
    local elapsed_ms

    async.run(token, function()
      local start = vim.uv.hrtime()
      async.sleep(200)
      elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    end)

    async.sleep(10)
    token.cancel()
    async.sleep(20)

    assert(elapsed_ms and elapsed_ms < 60, ("expected ~10ms, got %s"):format(tostring(elapsed_ms)))
  end)
end)
