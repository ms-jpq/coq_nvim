local T = require "coq.lib.test"
local async = require "coq.lib.async"

local capture_notify = function(marker)
  local state = { captured = nil }
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    if type(msg) == "string" and msg:find(marker, 1, true) then
      state.captured = { msg = msg, level = level }
    else
      return orig(msg, level, opts)
    end
  end
  state.restore = function()
    vim.notify = orig
  end
  return state
end

T.describe("async", function(test)
  test("awaitify forwards multiple callback values", function()
    local pack = async.awaitify(function(cb)
      cb("lil", "spot", "fido")
    end)
    local a, b, c = pack()

    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)

  test("entry defers execution", function()
    local ran = false
    local later = async.entry(function()
      ran = true
    end)

    T.eq(ran, false)

    vim.schedule(later)
    async.sleep(5)

    T.eq(ran, true)
  end)

  test("entry post-yield error surfaces via vim.notify", function()
    local marker = "fido bolted post-sleep"
    local cap = capture_notify(marker)

    vim.schedule(async.entry(function()
      async.sleep(2)
      error(marker)
    end))
    async.sleep(30)
    cap.restore()

    assert(cap.captured ~= nil, "expected vim.notify to fire for post-yield error")
    assert(cap.captured.msg:find(marker, 1, true), "expected marker in msg, got: " .. tostring(cap.captured.msg))
    T.eq(cap.captured.level, vim.log.levels.ERROR)
  end)

  test("entry post-yield error does not block sibling coroutines", function()
    local marker = "spot bolted post-sleep"
    local cap = capture_notify(marker)
    local sibling_ran = false

    vim.schedule(async.entry(function()
      async.sleep(2)
      error(marker)
    end))
    vim.schedule(async.entry(function()
      async.sleep(5)
      sibling_ran = true
    end))
    async.sleep(30)
    cap.restore()

    T.eq(sibling_ran, true)
  end)

  test("wrap forwards multi-value yields", function()
    local pull = async.wrap(function()
      coroutine.yield("lil", "spot", "fido")
    end)
    local a, b, c = pull()

    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)

  test("sleep yields for the requested duration", function()
    local start = vim.uv.hrtime()

    async.sleep(20)
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert(elapsed_ms >= 15, ("expected ~20ms, got %.1fms"):format(elapsed_ms))
  end)
end)
