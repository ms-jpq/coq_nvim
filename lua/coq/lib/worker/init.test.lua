local T = require "coq.lib.test"
local lib = require "coq.lib"
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
        return { name = "lil" }
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
        return "lil", 7, true
      end,
    }
    local a, b, c = w.pack()
    w.close()

    T.eq(a, "lil")
    T.eq(b, 7)
    T.eq(c, true)
  end)

  test("method errors propagate", function()
    local w = worker.spawn {
      bork = function()
        error "lil went missing"
      end,
      ok = function()
        return "still alive"
      end,
    }
    local ok, err = pcall(w.bork)
    local r = w.ok()
    w.close()

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected error message, got: " .. tostring(err))
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
          error "lil went missing"
        end)
      end,
    }
    local ok, err = pcall(w.bork)
    w.close()

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected main error, got: " .. tostring(err))
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
        yield "lil"
        yield "spot"
        yield "fido"
      end),
    }
    local seen = {}
    for dog in w.dogs() do
      table.insert(seen, dog)
    end
    w.close()

    T.eq(seen, { "lil", "spot", "fido" })
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
        yield "lil"
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

    T.eq(seen, { "lil" })
    T.eq(ok, false)
    assert(err:find "leash snapped", "expected leash snapped, got: " .. tostring(err))
  end)

  test("vim.iter is available inside the worker", function()
    local w = worker.spawn {
      reversed = function(_, items)
        local out = {}
        for v in vim.iter(items):rev() do
          table.insert(out, v)
        end
        return out
      end,
    }
    local seen = w.reversed { "lil", "spot", "fido" }
    w.close()

    T.eq(seen, { "fido", "spot", "lil" })
  end)

  test("vim.ringbuf is available inside the worker", function()
    local w = worker.spawn {
      init = function()
        return { rb = vim.ringbuf(3) }
      end,
      push = function(state, v)
        state.rb:push(v)
      end,
      drain = function(state)
        local out = {}
        for v in state.rb do
          table.insert(out, v)
        end
        return out
      end,
    }
    w.push "lil"
    w.push "spot"
    w.push "fido"
    w.push "rex"
    local seen = w.drain()
    w.close()

    T.eq(seen, { "spot", "fido", "rex" })
  end)

  test("close before the streaming fn's first yield unblocks it", function()
    local w = worker.spawn {
      init = function()
        return {
          done = require("coq.lib.async").future(),
          closed_cleanly = false,
        }
      end,
      delayed = worker.streaming(function(yield, state)
        require("coq.lib.worker").main(function() end)
        local cont = yield "lil"
        if not cont then
          state.closed_cleanly = true
        end
        state.done.resolve()
      end),
      wait_done = function(state)
        state.done.await()
        return state.closed_cleanly
      end,
    }

    local iter = w.delayed()
    iter.close()
    local ok = w.wait_done()
    w.close()

    T.eq(ok, true)
  end)

  test("yield with no values raises", function()
    local w = worker.spawn {
      bork = worker.streaming(function(yield, _)
        yield()
      end),
    }
    local ok, err = pcall(function()
      for _ in w.bork() do
      end
    end)
    w.close()

    T.eq(ok, false)
    assert(err and err:find "yield", "expected yield error, got: " .. tostring(err))
  end)

  test("proxy close is idempotent", function()
    local w = worker.spawn {
      ping = function()
        return "pong"
      end,
    }
    w.close()
    w.close()
  end)

  test("method call after close raises", function()
    local w = worker.spawn {
      ping = function()
        return "pong"
      end,
    }
    w.close()
    local ok, err = pcall(w.ping)

    T.eq(ok, false)
    assert(err and err:find "worker closed", "expected worker closed, got: " .. tostring(err))
  end)

  test("two streaming methods run with independent ids", function()
    local w = worker.spawn {
      counts = worker.streaming(function(yield, _, n)
        for i = 1, n do
          yield(i)
        end
      end),
    }
    local a, b = w.counts(3), w.counts(2)
    local seen_a, seen_b = {}, {}
    for v in a do
      table.insert(seen_a, v)
    end
    for v in b do
      table.insert(seen_b, v)
    end
    w.close()

    T.eq(seen_a, { 1, 2, 3 })
    T.eq(seen_b, { 1, 2 })
  end)

  test("streaming method can call back to main mid-stream", function()
    local w = worker.spawn {
      drip = worker.streaming(function(yield, _)
        local worker = require "coq.lib.worker"
        for _, name in pairs { "lil", "spot", "fido" } do
          local upper = worker.main(function(x)
            return x:upper()
          end, name)
          yield(upper)
        end
      end),
    }
    local seen = {}
    for v in w.drip() do
      table.insert(seen, v)
    end
    w.close()

    T.eq(seen, { "LIL", "SPOT", "FIDO" })
  end)

  test("close mid-stream is sticky for subsequent yields", function()
    local w = worker.spawn {
      init = function()
        return {
          done = require("coq.lib.async").future(),
          closed_cleanly = false,
        }
      end,
      slow = worker.streaming(function(yield, state)
        yield "lil"
        local cont = yield "spot"
        if not cont then
          state.closed_cleanly = true
        end
        state.done.resolve()
      end),
      wait_done = function(state)
        state.done.await()
        return state.closed_cleanly
      end,
    }

    local iter = w.slow()
    iter()
    iter.close()
    local ok = w.wait_done()
    w.close()

    T.eq(ok, true)
  end)

  test("ambient cancel mid-call sends STOP to worker", function()
    local async = require "coq.lib.async"
    local handle = require "coq.lib.async.handle"
    local h = handle.new()
    local w = worker.spawn {
      init = function()
        return { got_stop = require("coq.lib.async").future() }
      end,
      waiter = worker.streaming(function(yield, state)
        require("coq.lib.worker").main(function() end)
        local cont = yield "lil"
        if not cont then
          state.got_stop.resolve()
        end
      end),
      wait_got_stop = function(state)
        state.got_stop.await()
        return true
      end,
    }

    async.scope(h, function(n)
      n.spawn(function()
        local iter = w.waiter()
        iter()
      end)
      h.cancel()
    end)

    local ok = w.wait_got_stop()
    w.close()

    T.eq(ok, true)
  end)

  test("scope + defer pairs cleanly with iter.close", function()
    local w = worker.spawn {
      infinite = worker.streaming(function(yield, _)
        local i = 0
        while true do
          i = i + 1
          if not yield(i) then
            return
          end
        end
      end),
      ping = function()
        return "pong"
      end,
    }
    local seen = lib.scope(function(defer)
      local iter = w.infinite()
      defer(iter.close)

      local out = {}
      for v in iter do
        table.insert(out, v)
        if v >= 4 then
          break
        end
      end
      return out
    end)
    local r = w.ping()
    w.close()

    T.eq(seen, { 1, 2, 3, 4 })
    T.eq(r, "pong")
  end)
end)
