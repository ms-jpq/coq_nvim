local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

T.describe("future cancel", function(test)
  test("await returns nil when ambient handle already cancelled", function()
    local h = handle.new()
    h.cancel()

    async.scope(h, function(n)
      n.spawn(function()
        local f = async.future()

        T.eq(f.await(runtime.current()), nil)
      end)
    end)
  end)

  test("await returns resolved value even when explicit handle cancelled", function()
    local h = handle.new()
    h.cancel()
    local f = async.future()
    f.resolve(2)

    T.eq(f.await(h), 2)
  end)

  test("await wakes with nil when cancelled mid-yield", function()
    local h = handle.new()
    local awoke = false
    local got
    async.scope(h, function(n)
      n.spawn(function()
        local f = async.future()
        got = f.await(runtime.current())
        awoke = true
      end)
      h.cancel()
    end)

    T.eq(awoke, true)
    T.eq(got, nil)
  end)

  test("resolve after cancel is silent", function()
    local h = handle.new()
    local resolve
    async.scope(h, function(n)
      n.spawn(function()
        local f = async.future()
        resolve = f.resolve
        f.await(runtime.current())
      end)
      h.cancel()
    end)
    local ok = pcall(resolve, "late")

    T.eq(ok, true)
  end)
end)

T.describe("sleep cancel", function(test)
  test("returns immediately when handle already cancelled", function()
    local h = handle.new()
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
    local h = handle.new()
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

  test("uncancellable sleep ignores ambient cancel", function()
    local h = handle.new()
    local elapsed_ms

    async.scope(h, function(n)
      n.spawn(function()
        local start = vim.uv.hrtime()
        async.sleep(10, false)
        elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      end)
      async.sleep(2)
      h.cancel()
    end)

    assert(elapsed_ms and elapsed_ms >= 8, ("expected ~10ms, got %s"):format(tostring(elapsed_ms)))
  end)

  test("does not leak watchers on the passed handle", function()
    local n = nursery.new()
    local h = n.handle

    local live = {}
    local orig_on_cancel = h.on_cancel
    h.on_cancel = function(fn)
      live[fn] = true
      local unwatch = orig_on_cancel(fn)
      return function()
        live[fn] = nil
        unwatch()
      end
    end

    n.spawn(function()
      for _ = 1, 5 do
        async.sleep(1)
      end
    end)
    n.join()

    T.eq(next(live), nil)
  end)
end)
