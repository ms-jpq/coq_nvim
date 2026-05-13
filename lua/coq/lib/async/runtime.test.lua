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

    T.eq(bark "lil", "lil:woof")
  end)

  test("wrap forwards multiple callback values", function()
    local pack = async.wrap(function(cb)
      cb("lil", "spot", "fido")
    end)
    local a, b, c = pack()

    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)

  test("thunk defers execution", function()
    local ran = false
    local later = async.thunk(function()
      ran = true
    end)

    T.eq(ran, false)

    vim.schedule(later)
    async.sleep(5)

    T.eq(ran, true)
  end)

  test("thunk propagates errors", function()
    local ok
    vim.schedule(function()
      ok = pcall(function()
        async.thunk(function()
          error "lil went missing"
        end)()
      end)
    end)
    async.sleep(5)

    T.eq(ok, false)
  end)

  test("sleep yields for the requested duration", function()
    local start = vim.uv.hrtime()
    async.sleep(20)
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert(elapsed_ms >= 15, ("expected ~20ms, got %.1fms"):format(elapsed_ms))
  end)
end)
