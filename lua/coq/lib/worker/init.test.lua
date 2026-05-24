local T = require "coq.lib.test"
local lib = require "coq.lib"
local worker = require "coq.lib.worker"

T.describe("worker", function(test)
  test("globals persist across queues on the same worker", function()
    local w = worker.spawn()
    w.queue(function()
      _G.tricks = 0
    end)
    w.queue(function()
      _G.tricks = _G.tricks + 1
    end)
    w.queue(function()
      _G.tricks = _G.tricks + 1
    end)
    local n = w.queue(function()
      return _G.tricks
    end)
    w.close()

    T.eq(n, 2)
  end)

  test("queue forwards args", function()
    local w = worker.spawn()
    local g = w.queue(function(greeting, name)
      return greeting .. ", " .. name
    end, "hi", "spot")
    w.close()

    T.eq(g, "hi, spot")
  end)

  test("multi-return from a queued fn", function()
    local w = worker.spawn()
    local a, b, c = w.queue(function()
      return "lil", 7, true
    end)
    w.close()

    T.eq(a, "lil")
    T.eq(b, 7)
    T.eq(c, true)
  end)

  test("queue errors propagate and the worker survives", function()
    local w = worker.spawn()
    local ok, err = pcall(w.queue, function()
      error "lil went missing"
    end)
    local r = w.queue(function()
      return "still alive"
    end)
    w.close()

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected error message, got: " .. tostring(err))
    T.eq(r, "still alive")
  end)

  test("oneshot error reports user call site, not worker internals", function()
    local w = worker.spawn()
    local ok, err = pcall(w.queue, function()
      error "lil went missing"
    end)
    w.close()

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected message, got: " .. tostring(err))
    assert(err:find "init.test.lua", "error should point at user file, got: " .. tostring(err))
    assert(not err:find "worker/init.lua", "error must not point inside worker, got: " .. tostring(err))
  end)

  test("streaming error reports user iteration site, not worker internals", function()
    local w = worker.spawn()
    local ok, err = pcall(function()
      for _ in
        w.queue_stream(function(yield)
          yield "lil"
          error "leash snapped"
        end)
      do
      end
    end)
    w.close()

    T.eq(ok, false)
    assert(err:find "leash snapped", "expected message, got: " .. tostring(err))
    assert(err:find "init.test.lua", "error should point at user file, got: " .. tostring(err))
    assert(not err:find "worker/init.lua", "error must not point inside worker, got: " .. tostring(err))
  end)

  test("a queued fn can yield via async", function()
    local w = worker.spawn()
    local start = vim.uv.hrtime()
    w.queue(function()
      require("coq.lib.async").sleep(5)
    end)
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    w.close()

    assert(elapsed_ms >= 3, ("expected ~5ms, got %.1fms"):format(elapsed_ms))
  end)

  test("a queued fn can call back to main via worker.main", function()
    local expected = vim.fn.getcwd()
    local w = worker.spawn()
    local cwd_from_worker = w.queue(function()
      return require("coq.lib.worker").main(function()
        return vim.fn.getcwd()
      end)
    end)
    w.close()

    T.eq(cwd_from_worker, expected)
  end)

  test("worker.main forwards args", function()
    local w = worker.spawn()
    local r = w.queue(function(a, b)
      return require("coq.lib.worker").main(function(x, y)
        return x + y
      end, a, b)
    end, 3, 4)
    w.close()

    T.eq(r, 7)
  end)

  test("worker.main propagates errors from main", function()
    local w = worker.spawn()
    local ok, err = pcall(w.queue, function()
      return require("coq.lib.worker").main(function()
        error "lil went missing"
      end)
    end)
    w.close()

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected main error, got: " .. tostring(err))
  end)

  test("worker.main fn can yield via async", function()
    local expected = vim.fn.getcwd()
    local w = worker.spawn()
    local r = w.queue(function()
      return require("coq.lib.worker").main(function()
        require("coq.lib.async.vim").scheduled()
        return vim.fn.getcwd()
      end)
    end)
    w.close()

    T.eq(r, expected)
  end)

  test("queue_stream yields values to a for loop", function()
    local w = worker.spawn()
    local seen = {}
    for dog in
      w.queue_stream(function(yield)
        yield "lil"
        yield "spot"
        yield "fido"
      end)
    do
      table.insert(seen, dog)
    end
    w.close()

    T.eq(seen, { "lil", "spot", "fido" })
  end)

  test("queue_stream forwards args", function()
    local w = worker.spawn()
    local seen = {}
    for v in
      w.queue_stream(function(yield, n)
        for i = 1, n do
          yield(i)
        end
      end, 4)
    do
      table.insert(seen, v)
    end
    w.close()

    T.eq(seen, { 1, 2, 3, 4 })
  end)

  test("queue_stream propagates errors", function()
    local w = worker.spawn()
    local seen = {}
    local ok, err = pcall(function()
      for v in
        w.queue_stream(function(yield)
          yield "lil"
          error "leash snapped"
        end)
      do
        table.insert(seen, v)
      end
    end)
    w.close()

    T.eq(seen, { "lil" })
    T.eq(ok, false)
    assert(err:find "leash snapped", "expected leash snapped, got: " .. tostring(err))
  end)

  test("close before the streaming fn's first yield unblocks it", function()
    local w = worker.spawn()
    w.queue(function()
      _G.done = require("coq.lib.async.event").new()
      _G.closed_cleanly = false
    end)
    local iter = w.queue_stream(function(yield)
      local cont = yield "lil"
      if not cont then
        _G.closed_cleanly = true
      end
      _G.done.set()
    end)
    iter.close()
    local ok = w.queue(function()
      _G.done.wait()
      return _G.closed_cleanly
    end)
    w.close()

    T.eq(ok, true)
  end)

  test("yield with no values raises", function()
    local w = worker.spawn()
    local ok, err = pcall(function()
      for _ in
        w.queue_stream(function(yield)
          yield()
        end)
      do
      end
    end)
    w.close()

    T.eq(ok, false)
    assert(err and err:find "yield", "expected yield error, got: " .. tostring(err))
  end)

  test("yield with nil arg raises", function()
    local w = worker.spawn()
    local ok, err = pcall(function()
      for _ in
        w.queue_stream(function(yield)
          yield "lil"
          yield(nil)
        end)
      do
      end
    end)
    w.close()

    T.eq(ok, false)
    assert(err and err:find "nil value", "expected nil value error, got: " .. tostring(err))
  end)

  test("close is idempotent", function()
    local w = worker.spawn()
    w.close()
    w.close()
  end)

  test("queue after close raises", function()
    local w = worker.spawn()
    w.close()
    local ok, err = pcall(w.queue, function()
      return "pong"
    end)

    T.eq(ok, false)
    assert(err and err:find "worker closed", "expected worker closed, got: " .. tostring(err))
  end)

  test("queue_stream can call back to main mid-stream", function()
    local w = worker.spawn()
    local seen = {}
    for v in
      w.queue_stream(function(yield)
        local worker = require "coq.lib.worker"
        for _, name in pairs { "lil", "spot", "fido" } do
          local upper = worker.main(function(x)
            return x:upper()
          end, name)
          yield(upper)
        end
      end)
    do
      table.insert(seen, v)
    end
    w.close()

    T.eq(seen, { "LIL", "SPOT", "FIDO" })
  end)

  test("close mid-stream is sticky for subsequent yields", function()
    local w = worker.spawn()
    w.queue(function()
      _G.done = require("coq.lib.async.event").new()
      _G.closed_cleanly = false
    end)
    local iter = w.queue_stream(function(yield)
      yield "lil"
      local cont = yield "spot"
      if not cont then
        _G.closed_cleanly = true
      end
      _G.done.set()
    end)
    iter()
    iter.close()
    local ok = w.queue(function()
      _G.done.wait()
      return _G.closed_cleanly
    end)
    w.close()

    T.eq(ok, true)
  end)

  test("ambient cancel mid-call sends STOP to worker", function()
    local async = require "coq.lib.async"
    local handle = require "coq.lib.async.handle"
    local h = handle.new()
    local w = worker.spawn()
    w.queue(function()
      _G.got_stop = require("coq.lib.async.event").new()
    end)

    async.scope(h, function(n)
      n.spawn(function()
        local iter = w.queue_stream(function(yield)
          local cont = yield "lil"
          if not cont then
            _G.got_stop.set()
          end
        end)
        iter()
      end)
      h.cancel()
    end)

    local ok = w.queue(function()
      _G.got_stop.wait()
      return true
    end)
    w.close()

    T.eq(ok, true)
  end)

  test("uniterated stream is cleaned up on ambient cancel", function()
    local async = require "coq.lib.async"
    local handle = require "coq.lib.async.handle"
    local h = handle.new()
    local w = worker.spawn()
    w.queue(function()
      _G.got_stop = require("coq.lib.async.event").new()
    end)

    async.scope(h, function(n)
      n.spawn(function()
        local _iter = w.queue_stream(function(yield)
          while yield "tick" do
          end
          _G.got_stop.set()
        end)
      end)
      h.cancel()
    end)

    local ok = w.queue(function()
      _G.got_stop.wait()
      return true
    end)
    w.close()

    T.eq(ok, true)
  end)

  test("ambient cancel propagates through worker.main", function()
    local async = require "coq.lib.async"
    local handle = require "coq.lib.async.handle"
    local runtime = require "coq.lib.async.runtime"
    local h = handle.new()
    local w = worker.spawn()
    w.queue(function()
      _G.got_cancel = require("coq.lib.async.event").new()
    end)

    async.scope(h, function(n)
      n.spawn(function()
        local iter = w.queue_stream(function(yield)
          local r = require("coq.lib.worker").main(function()
            require("coq.lib.async").sleep(10000)
            return "should not reach"
          end)
          if r == nil then
            _G.got_cancel.set()
          end
        end)
        local _ = runtime.current().on_cancel(iter.close)
        iter()
      end)
      h.cancel()
    end)

    local ok = w.queue(function()
      _G.got_cancel.wait()
      return true
    end)
    w.close()

    T.eq(ok, true)
  end)

  test("scope + defer pairs cleanly with iter.close", function()
    local w = worker.spawn()
    local seen = lib.scope(function(defer)
      local iter = w.queue_stream(function(yield)
        local i = 0
        while true do
          i = i + 1
          if not yield(i) then
            return
          end
        end
      end)
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
    local r = w.queue(function()
      return "pong"
    end)
    w.close()

    T.eq(seen, { 1, 2, 3, 4 })
    T.eq(r, "pong")
  end)

  test("a streaming fn that never yields returns nil immediately", function()
    local w = worker.spawn()
    local iter = w.queue_stream(function()
      -- never calls yield
    end)
    local first = iter()
    w.close()

    T.eq(first, nil)
  end)

  test("concurrent queues do not cross-talk", function()
    local async = require "coq.lib.async"
    local w = worker.spawn()
    local results = {}
    async.scope(function(n)
      for i = 1, 5 do
        n.spawn(function()
          results[i] = w.queue(function(delay_ms, label)
            require("coq.lib.async").sleep(delay_ms)
            return label
          end, i * 2, "dog_" .. i)
        end)
      end
    end)
    w.close()

    T.eq(results, { "dog_1", "dog_2", "dog_3", "dog_4", "dog_5" })
  end)

  test("two streams interleave independently", function()
    local async = require "coq.lib.async"
    local w = worker.spawn()
    local seen_a, seen_b = {}, {}
    async.scope(function(n)
      n.spawn(function()
        for v in
          w.queue_stream(function(yield, count, prefix)
            for i = 1, count do
              yield(prefix .. i)
            end
          end, 3, "a")
        do
          table.insert(seen_a, v)
        end
      end)
      n.spawn(function()
        for v in
          w.queue_stream(function(yield, count, prefix)
            for i = 1, count do
              yield(prefix .. i)
            end
          end, 3, "b")
        do
          table.insert(seen_b, v)
        end
      end)
    end)
    w.close()

    T.eq(seen_a, { "a1", "a2", "a3" })
    T.eq(seen_b, { "b1", "b2", "b3" })
  end)
end)
