local T = require "coq.lib.test"
local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

T.describe("atools.spawn", function(test)
  test("captures stdout, stderr, and exit code", function()
    local result
    async.scope(function()
      result = atools.spawn { "sh", "-c", "printf fido; printf lil >&2; exit 7" }
    end)
    T.eq(result.code, 7)
    T.eq(result.signal, 0)
    T.eq(result.stdout, "fido")
    T.eq(result.stderr, "lil")
  end)

  test("writes stdin and the child reads it back", function()
    local result
    async.scope(function()
      result = atools.spawn({ "cat" }, { stdin = "fido\nlil\nspot" })
    end)
    T.eq(result.code, 0)
    T.eq(result.stdout, "fido\nlil\nspot")
  end)

  test("ambient cancel kills the child before it finishes naturally", function()
    local elapsed_ms
    async.scope(function(n)
      n.spawn(function()
        local start = vim.uv.hrtime()
        pcall(atools.spawn, { "sleep", "60" })
        elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      end)
      async.sleep(5 * T.SLOW)
      n.handle.cancel()
    end)
    assert(elapsed_ms and elapsed_ms < 100 * T.SLOW, "expected fast kill, got " .. tostring(elapsed_ms) .. " ms")
  end)
end)
