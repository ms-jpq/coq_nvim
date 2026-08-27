local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local handle = require "coq.lib.async._handle"
local nursery = require "coq.lib.async._nursery"
local runtime = require "coq.lib.async._runtime"

T.describe({ "future cancel" }, function(test)
  test({ "await throws cancel when ambient handle already cancelled" }, function()
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

  test({ "await throws cancel even when future also resolved" }, function()
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

  test({ "await wakes by throwing cancel when cancelled mid-yield" }, function()
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

  test({ "resolve after cancel is silent" }, function()
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

  test({ "cancel removes the future subscription" }, function()
    local f = async.future()
    local live = {}
    local once_ready = f.once_ready
    f.once_ready = function(cb)
      live[cb] = true
      local unready = once_ready(cb)
      return function()
        live[cb] = nil
        unready()
      end
    end

    local h = handle.new()
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      pcall(f.await)
    end)
    async.sleep(0)
    T.eq(next(live) ~= nil, true)
    h.cancel()
    n.join()
    T.eq(next(live), nil)
  end)
end)

T.describe({ "sleep cancel" }, function(test)
  test({ "returns immediately when handle already cancelled" }, function()
    -- Pre-cancel the handle, then call sleep. The pcall raises cancel — if
    -- sleep actually waited, the sentinel sibling would log first.
    local h = handle.new()
    local checkpoints = {}
    async.scope(function(outer)
      outer.spawn(function()
        async.sleep(50 * T.SLOW)
        table.insert(checkpoints, "sentinel")
      end)
      local n = nursery.new()
      local _ = h.on_cancel(n.cancel)
      n.spawn(function()
        h.cancel()
        pcall(async.sleep, 100 * T.SLOW)
        table.insert(checkpoints, "woke")
      end)
      n.join()
      outer.cancel()
    end)
    T.eq(checkpoints, { "woke" })
  end)

  test({ "throws cancel when cancelled mid-sleep" }, function()
    -- pcall flagging the cancel error IS the proof; if the cancel didn't
    -- interrupt, pcall would return ok=true.
    local h = handle.new()
    local ok, err

    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      ok, err = pcall(async.sleep, 500 * T.SLOW)
    end)
    n.spawn(function()
      async.sleep(30 * T.SLOW)
      h.cancel()
    end)
    n.join()

    T.eq(ok, false)
    T.eq(cancel.is(err), true)
  end)

  test({ "does not leak watchers on the ambient handle" }, function()
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
    runtime._detach(h, function()
      for _ = 1, 5 do
        async.sleep(1 * T.SLOW)
      end
      done.resolve()
    end)
    done.await()

    T.eq(next(live), nil)
  end)
end)

T.describe({ "defer async" }, function(test)
  test({ "a future can be awaited inside a defer" }, function()
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

  test({ "an async.wrap can be iterated inside a defer" }, function()
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
