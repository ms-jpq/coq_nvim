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

  test("method can call back to main via worker.main", function()
    local expected = vim.fn.getcwd()
    local w = worker.spawn {
      get_cwd = function()
        local worker = require "coq.lib.worker"
        return worker.main(function()
          return vim.fn.getcwd()
        end)
      end,
    }
    local cwd_from_worker = w.get_cwd()
    w.close()
    T.eq(cwd_from_worker, expected)
  end)

  test("worker.main forwards args", function()
    local w = worker.spawn {
      add = function(_, a, b)
        local worker = require "coq.lib.worker"
        return worker.main(function(x, y)
          return x + y
        end, a, b)
      end,
    }
    local r = w.add(3, 4)
    w.close()
    T.eq(r, 7)
  end)

  test("worker.main propagates errors from main", function()
    local w = worker.spawn {
      bork = function()
        local worker = require "coq.lib.worker"
        return worker.main(function()
          error "rex went missing"
        end)
      end,
    }
    local ok, err = pcall(w.bork)
    w.close()
    T.eq(ok, false)
    assert(err:find "rex went missing", "expected main error, got: " .. tostring(err))
  end)

  test("worker.main fn can yield via async", function()
    local expected = vim.fn.getcwd()
    local w = worker.spawn {
      slow_cwd = function()
        local worker = require "coq.lib.worker"
        return worker.main(function()
          local avim = require "coq.lib.async.vim"
          avim.scheduled()
          return vim.fn.getcwd()
        end)
      end,
    }
    local r = w.slow_cwd()
    w.close()
    T.eq(r, expected)
  end)

  test("streaming method yields values to a for loop", function()
    local w = worker.spawn {
      dogs = worker.streaming(function(yield, _)
        yield "rex"
        yield "spot"
        yield "fido"
      end),
    }
    local seen = {}
    for dog in w.dogs() do
      table.insert(seen, dog)
    end
    w.close()
    T.eq(seen, { "rex", "spot", "fido" })
  end)

  test("streaming method forwards args", function()
    local w = worker.spawn {
      counted = worker.streaming(function(yield, _, n)
        for i = 1, n do
          yield(i)
        end
      end),
    }
    local seen = {}
    for v in w.counted(4) do
      table.insert(seen, v)
    end
    w.close()
    T.eq(seen, { 1, 2, 3, 4 })
  end)

  test("streaming method propagates errors", function()
    local w = worker.spawn {
      bork = worker.streaming(function(yield, _)
        yield "rex"
        error "leash snapped"
      end),
    }
    local seen = {}
    local ok, err = pcall(function()
      for v in w.bork() do
        table.insert(seen, v)
      end
    end)
    w.close()
    T.eq(seen, { "rex" })
    T.eq(ok, false)
    assert(err:find "leash snapped", "expected leash snapped, got: " .. tostring(err))
  end)

  test("unknown method returns error", function()
    local w = worker.spawn {
      known = function()
        return "ok"
      end,
    }
    T.eq(w.known(), "ok")
    w.close()
  end)
end)
