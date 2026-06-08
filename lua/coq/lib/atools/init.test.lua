local T = require "coq.lib.test"
local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

T.describe({ "atools.spawn" }, function(test)
  test({ "captures stdout, stderr, and exit code" }, function()
    local result
    async.scope(function()
      result = atools.spawn { "sh", "-c", "printf fido; printf lil >&2; exit 7" }
    end)
    T.eq(result.code, 7)
    T.eq(result.signal, 0)
    T.eq(result.stdout, "fido")
    T.eq(result.stderr, "lil")
  end)

  test({ "writes stdin and the child reads it back" }, function()
    local result
    async.scope(function()
      result = atools.spawn({ "cat" }, { stdin = "fido\nlil\nspot" })
    end)
    T.eq(result.code, 0)
    T.eq(result.stdout, "fido\nlil\nspot")
  end)

  test({ "ambient cancel kills the child before it finishes naturally" }, function()
    -- pcall returning ok=false IS the proof the child was killed. If
    -- cancel didn't propagate, atools.spawn would wait the full `sleep 60`
    -- and pcall would return ok=true.
    local child_ok
    async.scope(function(n)
      n.spawn(function()
        child_ok = pcall(atools.spawn, { "sleep", "60" })
      end)
      async.sleep(5 * T.SLOW)
      n.cancel()
    end)
    T.eq(child_ok, false)
  end)
end)
