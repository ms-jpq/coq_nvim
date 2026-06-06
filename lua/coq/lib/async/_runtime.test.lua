local T = require "coq.lib.test"
local async = require "coq.lib.async"

---@class runtime.test.Capture
---@field msg string
---@field level integer

local CAPTURES = {}
local ORIG_NOTIFY = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, level, opts)
  if type(msg) == "string" then
    for marker, state in pairs(CAPTURES) do
      if msg:find(marker, 1, true) then
        state.captured = { msg = msg, level = level }
        if state.done then
          state.done.resolve()
        end
        return
      end
    end
  end
  return ORIG_NOTIFY(msg, level, opts)
end

local capture_notify = function(marker)
  local state = {
    ---@type runtime.test.Capture?
    captured = nil,
    done = async.future(),
  }
  CAPTURES[marker] = state
  state.restore = function()
    CAPTURES[marker] = nil
  end
  return state
end

T.describe({ "async" }, function(test)
  test({ "awaitify forwards multiple callback values" }, function()
    local pack = async.awaitify(function(cb)
      cb("lil", "spot", "fido")
    end)
    local a, b, c = pack()

    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)

  test({ "entry defers execution" }, function()
    local done = async.future()
    local ran = false
    local later = async.entry(function()
      ran = true
      done.resolve()
    end)

    T.eq(ran, false)

    vim.schedule(later)
    done.await()

    T.eq(ran, true)
  end)

  test({ "entry post-yield error surfaces via vim.notify" }, function()
    local marker = "fido bolted post-sleep"
    local cap = capture_notify(marker)

    vim.schedule(async.entry(function()
      async.sleep(2 * T.SLOW)
      error(marker)
    end))
    cap.done.await()
    cap.restore()

    assert(cap.captured ~= nil, "expected vim.notify to fire for post-yield error")
    assert(cap.captured.msg:find(marker, 1, true), "expected marker in msg, got: " .. tostring(cap.captured.msg))
    T.eq(cap.captured.level, vim.log.levels.ERROR)
  end)

  test({ "entry post-yield error does not block sibling coroutines" }, function()
    local marker = "spot bolted post-sleep"
    local cap = capture_notify(marker)
    local sibling_ran = false
    local sibling_done = async.future()

    vim.schedule(async.entry(function()
      async.sleep(2 * T.SLOW)
      error(marker)
    end))
    vim.schedule(async.entry(function()
      async.sleep(5 * T.SLOW)
      sibling_ran = true
      sibling_done.resolve()
    end))
    sibling_done.await()
    cap.done.await()
    cap.restore()

    T.eq(sibling_ran, true)
  end)

  test({ "wrap forwards multi-value yields" }, function()
    local pull = async.wrap(function()
      coroutine.yield("lil", "spot", "fido")
    end)
    local a, b, c = pull()

    T.eq({ a, b, c }, { "lil", "spot", "fido" })
  end)

  test({ "sleep yields for the requested duration" }, function()
    local start = vim.uv.hrtime()

    async.sleep(20 * T.SLOW)
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert(elapsed_ms >= 15 * T.SLOW, ("expected ~20ms, got %.1fms"):format(elapsed_ms))
  end)
end)
