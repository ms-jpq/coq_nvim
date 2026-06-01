local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local handle = require "coq.lib.async.handle"
local nursery = require "coq.lib.async.nursery"

T.describe("future cancel", function(test)
  test("await throws cancel when ambient handle already cancelled", function()
    local h = handle.new()
    h.cancel()

    local n = nursery.new()
    local _ = h.on_cancel(n.handle.cancel)
    n.spawn(function()
      local f = async.future()
      local ok, err = pcall(f.await)
      T.eq(ok, false)
      T.eq(cancel.is(err), true)
    end)
    n.join()
  end)

  test("await throws cancel even when future also resolved", function()
    local h = handle.new()
    h.cancel()
    local f = async.future()
    f.resolve(2)

    local ok, err
    local n = nursery.new()
    local _ = h.on_cancel(n.handle.cancel)
    n.spawn(function()
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
    local _ = h.on_cancel(n.handle.cancel)
    n.spawn(function()
      local f = async.future()
      ok, err = pcall(f.await)
      awoke = true
    end)
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
    local _ = h.on_cancel(n.handle.cancel)
    n.spawn(function()
      local f = async.future()
      resolve = f.resolve
      pcall(f.await)
    end)
    h.cancel()
    n.join()
    local ok = pcall(resolve, "late")

    T.eq(ok, true)
  end)
end)

T.describe("sleep cancel", function(test)
  test("returns immediately when handle already cancelled", function()
    local h = handle.new()
    h.cancel()

    local n = nursery.new()
    local _ = h.on_cancel(n.handle.cancel)
    n.spawn(function()
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
    local _ = h.on_cancel(n.handle.cancel)
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
        async.sleep(1 * T.SLOW)
      end
    end)
    n.join()

    T.eq(next(live), nil)
  end)
end)
