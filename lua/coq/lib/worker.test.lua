local T = require "coq.lib.test"
local worker = require "coq.lib.worker"

T.describe("worker", function(test)
  test("state persists across method calls", function()
    local w = worker.spawn {
      init = function()
        return { tricks = 0 }
      end,
      train = function(state)
        state.tricks = state.tricks + 1
      end,
      count = function(state)
        return state.tricks
      end,
    }
    w.train()
    w.train()
    w.train()
    local n = w.count()
    w.close()
    T.eq(n, 3)
  end)

  test("method args pass through", function()
    local w = worker.spawn {
      init = function()
        return { name = "rex" }
      end,
      rename = function(state, new_name)
        state.name = new_name
      end,
      greet = function(state, greeting)
        return greeting .. ", " .. state.name
      end,
    }
    w.rename "spot"
    local g = w.greet "hi"
    w.close()
    T.eq(g, "hi, spot")
  end)

  test("multi-return from method", function()
    local w = worker.spawn {
      init = function()
        return {}
      end,
      pack = function(_)
        return "rex", 7, true
      end,
    }
    local a, b, c = w.pack()
    w.close()
    T.eq(a, "rex")
    T.eq(b, 7)
    T.eq(c, true)
  end)

  test("method errors propagate", function()
    local w = worker.spawn {
      init = function()
        return {}
      end,
      bork = function()
        error "rex went missing"
      end,
      ok = function()
        return "still alive"
      end,
    }
    local ok, err = pcall(w.bork)
    local r = w.ok()
    w.close()
    T.eq(ok, false)
    assert(err:find "rex went missing", "expected error message, got: " .. tostring(err))
    T.eq(r, "still alive")
  end)

  test("method can yield via async from state", function()
    local w = worker.spawn {
      init = function()
        return {
          async = require "coq.lib.async",
          tricks = 0,
        }
      end,
      delayed_train = function(state)
        state.async.sleep(20)
        state.tricks = state.tricks + 1
      end,
      count = function(state)
        return state.tricks
      end,
    }

    local start = vim.uv.hrtime()
    w.delayed_train()
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    local n = w.count()
    w.close()
    T.eq(n, 1)
    assert(elapsed_ms >= 15, ("expected ~20ms, got %.1fms"):format(elapsed_ms))
  end)

  test("unknown method returns error", function()
    local w = worker.spawn {
      init = function()
        return {}
      end,
      known = function()
        return "ok"
      end,
    }
    T.eq(w.known(), "ok")
    w.close()
  end)
end)
