local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local handle = require "coq.lib.async.handle"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

T.describe("future cancel", function(test)
  test("await throws cancel when ambient handle already cancelled", function()
    local h = handle.new()
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      h.cancel()
      local f = async.future()
      local ok, err = pcall(f.await)
      T.eq(ok, false)
      T.eq(cancel.is(err), true)
    end)
    n.join()
  end)

  test("await throws cancel even when future also resolved", function()
    local f = async.future()
    f.resolve(2)

    local ok, err
    local h = handle.new()
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      h.cancel()
      ok, err = pcall(f.await)
    end)
    n.join()
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
  end)

  test("await wakes by throwing cancel when cancelled mid-yield", function()
    local h = handle.new()
    local awoke = false
    local ok, err
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      local f = async.future()
      ok, err = pcall(f.await)
      awoke = true
    end)
    async.sleep(0)
    h.cancel()
    n.join()

    T.eq(awoke, true)
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
  end)

  test("resolve after cancel is silent", function()
    local h = handle.new()
    local resolve
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      local f = async.future()
      resolve = f.resolve
      pcall(f.await)
    end)
    async.sleep(0)
    h.cancel()
    n.join()
    local ok = pcall(resolve, "late")

    T.eq(ok, true)
  end)
end)

T.describe("sleep cancel", function(test)
  test("returns immediately when handle already cancelled", function()
    local h = handle.new()
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      h.cancel()
      local start = vim.uv.hrtime()
      pcall(async.sleep, 100 * T.SLOW)
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

      assert(elapsed_ms < 20 * T.SLOW, ("expected immediate, got %.1fms"):format(elapsed_ms))
    end)
    n.join()
  end)

  test("throws cancel when cancelled mid-sleep", function()
    local h = handle.new()
    local elapsed_ms
    local ok, err

    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      local start = vim.uv.hrtime()
      ok, err = pcall(async.sleep, 500 * T.SLOW)
      elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    end)
    n.spawn(function()
      async.sleep(30 * T.SLOW)
      h.cancel()
    end)
    n.join()

    assert(elapsed_ms and elapsed_ms < 200 * T.SLOW, ("expected fast wake, got %s"):format(tostring(elapsed_ms)))
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
  end)

  test("does not leak watchers on the ambient handle", function()
    local h = handle.new()
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

    local done = async.future()
    runtime.detach(h, function()
      for _ = 1, 5 do
        async.sleep(1 * T.SLOW)
      end
      done.resolve()
    end)
    done.await()

    T.eq(next(live), nil)
  end)
end)

T.describe("defer async", function(test)
  test("a future can be awaited inside a defer", function()
    local f = async.future()
    local got
    local n = nursery.new()
    n.spawn(function(defer)
      defer(function()
        got = f.await()
      end)
    end)
    n.spawn(function()
      async.sleep(0)
      f.resolve "spot"
    end)
    n.join()

    T.eq(got, "spot")
  end)

  test("an async.wrap can be iterated inside a defer", function()
    local seen = {}
    local n = nursery.new()
    n.spawn(function(defer)
      defer(function()
        local iter = async.wrap(function()
          coroutine.yield "spot"
          async.sleep(0)
          coroutine.yield "fido"
        end)
        for v in iter do
          table.insert(seen, v)
        end
      end)
    end)
    n.join()

    T.eq(seen, { "spot", "fido" })
  end)
end)
