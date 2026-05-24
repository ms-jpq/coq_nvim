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

  test("oneshot error reports user call site, not worker internals", function()
    local w = worker.spawn {
      bork = function()
        error "lil went missing"
      end,
    }
    local ok, err = pcall(w.bork)
    w.close()

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected message, got: " .. tostring(err))
    assert(err:find "init.test.lua", "error should point at user file, got: " .. tostring(err))
    assert(not err:find "worker/init.lua", "error must not point inside worker, got: " .. tostring(err))
  end)

  test("streaming error reports user iteration site, not worker internals", function()
    local w = worker.spawn {
      bork = worker.streaming(function(yield, _)
        yield "lil"
        error "leash snapped"
      end),
    }
    local ok, err = pcall(function()
      for _ in w.bork() do
      end
    end)
    w.close()

    T.eq(ok, false)
    assert(err:find "leash snapped", "expected message, got: " .. tostring(err))
    assert(err:find "init.test.lua", "error should point at user file, got: " .. tostring(err))
    assert(not err:find "worker/init.lua", "error must not point inside worker, got: " .. tostring(err))
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
        state.async.sleep(5)
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
    assert(elapsed_ms >= 3, ("expected ~5ms, got %.1fms"):format(elapsed_ms))
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

  test("close before the streaming fn's first yield unblocks it", function()
    local w = worker.spawn {
      init = function()
        return {
          done = require("coq.lib.async.event").new(),
          closed_cleanly = false,
        }
      end,
      delayed = worker.streaming(function(yield, state)
        local cont = yield "lil"
        if not cont then
          state.closed_cleanly = true
        end
        state.done.set()
      end),
      wait_done = function(state)
        state.done.wait()
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

  test("yield with nil arg raises", function()
    local w = worker.spawn {
      bork = worker.streaming(function(yield, _)
        yield "lil"
        yield(nil)
      end),
    }
    local ok, err = pcall(function()
      for _ in w.bork() do
      end
    end)
    w.close()

    T.eq(ok, false)
    assert(err and err:find "nil value", "expected nil value error, got: " .. tostring(err))
  end)

  test("spawn rejects a method named 'close'", function()
    local ok, err = pcall(worker.spawn, {
      close = function()
        return "bark"
      end,
    })

    T.eq(ok, false)
    assert(err and err:find "'close' is reserved", "expected reserved-name error, got: " .. tostring(err))
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
          done = require("coq.lib.async.event").new(),
          closed_cleanly = false,
        }
      end,
      slow = worker.streaming(function(yield, state)
        yield "lil"
        local cont = yield "spot"
        if not cont then
          state.closed_cleanly = true
        end
        state.done.set()
      end),
      wait_done = function(state)
        state.done.wait()
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
        return { got_stop = require("coq.lib.async.event").new() }
      end,
      waiter = worker.streaming(function(yield, state)
        local cont = yield "lil"
        if not cont then
          state.got_stop.set()
        end
      end),
      wait_got_stop = function(state)
        state.got_stop.wait()
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

  test("uniterated stream is cleaned up on ambient cancel", function()
    local async = require "coq.lib.async"
    local handle = require "coq.lib.async.handle"
    local h = handle.new()
    local w = worker.spawn {
      init = function()
        return { got_stop = require("coq.lib.async.event").new() }
      end,
      forever = worker.streaming(function(yield, state)
        while yield "tick" do
        end
        state.got_stop.set()
      end),
      wait_got_stop = function(state)
        state.got_stop.wait()
        return true
      end,
    }

    async.scope(h, function(n)
      n.spawn(function()
        local _iter = w.forever()
      end)
      h.cancel()
    end)

    local ok = w.wait_got_stop()
    w.close()

    T.eq(ok, true)
  end)

  test("ambient cancel propagates through worker.main", function()
    local async = require "coq.lib.async"
    local handle = require "coq.lib.async.handle"
    local runtime = require "coq.lib.async.runtime"
    local h = handle.new()
    local w = worker.spawn {
      init = function()
        return { got_cancel = require("coq.lib.async.event").new() }
      end,
      waiter = worker.streaming(function(yield, state)
        local r = require("coq.lib.worker").main(function()
          require("coq.lib.async").sleep(10000)
          return "should not reach"
        end)
        if r == nil then
          state.got_cancel.set()
        end
      end),
      wait_cancel = function(state)
        state.got_cancel.wait()
        return true
      end,
    }

    async.scope(h, function(n)
      n.spawn(function()
        local iter = w.waiter()
        local _ = runtime.current().on_cancel(iter.close)
        iter()
      end)
      h.cancel()
    end)

    local ok = w.wait_cancel()
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

  test("streaming method that never yields returns nil immediately", function()
    local w = worker.spawn {
      silent = worker.streaming(function(_, _)
        -- never calls yield
      end),
    }
    local iter = w.silent()
    local first = iter()
    w.close()

    T.eq(first, nil)
  end)

  test("concurrent oneshot calls do not cross-talk", function()
    local async = require "coq.lib.async"
    local w = worker.spawn {
      echo = function(_, delay_ms, label)
        local async = require "coq.lib.async"
        async.sleep(delay_ms)
        return label
      end,
    }
    local results = {}
    async.scope(function(n)
      for i = 1, 5 do
        n.spawn(function()
          results[i] = w.echo(i * 2, "dog_" .. i)
        end)
      end
    end)
    w.close()

    T.eq(results, { "dog_1", "dog_2", "dog_3", "dog_4", "dog_5" })
  end)

  test("two streaming iters from same method interleave independently", function()
    local async = require "coq.lib.async"
    local w = worker.spawn {
      counted = worker.streaming(function(yield, _, n, prefix)
        for i = 1, n do
          yield(prefix .. i)
        end
      end),
    }
    local seen_a, seen_b = {}, {}
    async.scope(function(n)
      n.spawn(function()
        for v in w.counted(3, "a") do
          table.insert(seen_a, v)
        end
      end)
      n.spawn(function()
        for v in w.counted(3, "b") do
          table.insert(seen_b, v)
        end
      end)
    end)
    w.close()

    T.eq(seen_a, { "a1", "a2", "a3" })
    T.eq(seen_b, { "b1", "b2", "b3" })
  end)
end)
