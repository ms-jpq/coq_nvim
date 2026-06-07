local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async._handle"
local mpmc = require "coq.lib.channels.mpmc"
local runtime = require "coq.lib.async._runtime"

local delayed = function(value, delay)
  local sent = false
  return function()
    if sent then
      return nil
    end
    async.sleep(delay)
    if runtime.current().cancelled then
      return nil
    end
    sent = true
    return value
  end
end

T.describe({ "merge" }, function(test)
  test({ "of one iter yields values until exhausted" }, function()
    local i = 0
    local iter = function()
      i = i + 1
      if i > 3 then
        return nil
      end
      async.sleep(2 * T.SLOW)
      return i * 10
    end

    local out = {}
    local _, m = async.merge { iter }
    for _, v in m do
      table.insert(out, v)
    end

    T.eq(out, { 10, 20, 30 })
  end)

  test({ "returns each iter's value in completion order" }, function()
    local out = {}
    local _, m = async.merge {
      delayed("a", 2 * T.SLOW),
      delayed("c", 6 * T.SLOW),
      delayed("b", 4 * T.SLOW),
    }
    for _, v in m do
      table.insert(out, v)
    end

    T.eq(out, { "a", "b", "c" })
  end)

  test({ "returns the original iter index alongside the value" }, function()
    local out = {}
    local _, m = async.merge {
      delayed("a", 2 * T.SLOW),
      delayed("c", 6 * T.SLOW),
      delayed("b", 4 * T.SLOW),
    }
    for idx, v in m do
      table.insert(out, { idx, v })
    end

    T.eq(out, { { 1, "a" }, { 3, "b" }, { 2, "c" } })
  end)

  test({ "returns nil when ambient handle cancelled mid-merge" }, function()
    local nursery = require "coq.lib.async._nursery"
    local h = handle.new()
    local got
    local n = nursery.new()
    local _ = h.on_cancel(n.cancel)
    n.spawn(function()
      local iter = function()
        async.sleep(100 * T.SLOW)
        return "never"
      end
      local _, m = async.merge { iter }
      got = m()
    end)
    h.cancel()
    n.join()

    T.eq(got, nil)
  end)

  test({ "close stops further pulls" }, function()
    local close, m = async.merge {
      function()
        async.sleep(100 * T.SLOW)
        return "never"
      end,
    }
    close()

    T.eq(m(), nil)
  end)

  test({ "close raises errors from a failed iter" }, function()
    local errored = async.future()
    local close, _ = async.merge {
      function()
        errored.resolve()
        error("bad dog", 0)
      end,
    }

    errored.await()
    local ok, err = pcall(close)
    T.eq(ok, false)
    T.eq(err, "bad dog")
  end)

  test({ "pull raises errors from a failed iter" }, function()
    local _, m = async.merge {
      function()
        async.sleep(2 * T.SLOW)
        error("bad dog", 0)
      end,
    }

    local ok, err = pcall(function()
      for _ in m do
      end
    end)
    T.eq(ok, false)
    T.eq(err, "bad dog")
  end)

  test({ "close cancels in-flight producers" }, function()
    local fired = false
    async.scope(function(n)
      n.spawn(function()
        local close, _ = async.merge {
          function()
            local _ = runtime.current().on_cancel(function()
              fired = true
            end)
            async.sleep(100 * T.SLOW)
            return "never"
          end,
        }
        async.sleep(5 * T.SLOW)
        close()
      end)
    end)

    T.eq(fired, true)
  end)

  test({ "accepts a channel pull as an iter" }, function()
    local chan = mpmc.new(math.huge)
    chan.push "spot"
    chan.push "fido"
    chan.close()

    local out = {}
    local _, m = async.merge { chan.pull }
    for _, v in m do
      table.insert(out, v)
    end

    T.eq(out, { "spot", "fido" })
  end)

  test({ "merges two channels, interleaved by push order" }, function()
    local a, b = mpmc.new(math.huge), mpmc.new(math.huge)

    async.scope(function(n)
      n.spawn(function()
        a.push "spot"
        async.sleep(2 * T.SLOW)
        b.push "fido"
        async.sleep(2 * T.SLOW)
        a.push "rex"
        a.close()
        b.close()
      end)

      n.spawn(function()
        local out = {}
        local _, m = async.merge { a.pull, b.pull }
        for idx, v in m do
          table.insert(out, { idx, v })
        end
        T.eq(out, { { 1, "spot" }, { 2, "fido" }, { 1, "rex" } })
      end)
    end)
  end)

  test({ "mixes async.wrap iters and channel pulls" }, function()
    local chan = mpmc.new(math.huge)
    chan.push "spot"
    chan.close()

    local wrapped = async.wrap(function()
      coroutine.yield "fido"
    end)

    local out = {}
    local _, m = async.merge { chan.pull, wrapped }
    for _, v in m do
      table.insert(out, v)
    end
    table.sort(out)

    T.eq(out, { "fido", "spot" })
  end)

  test({ "close unblocks a channel pull waiting on data" }, function()
    local chan = mpmc.new(math.huge)

    async.scope(function(n)
      n.spawn(function()
        local close, m = async.merge { chan.pull }
        async.sleep(2 * T.SLOW)
        close()
        T.eq(m(), nil)
      end)
    end)
  end)
end)
