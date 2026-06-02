local T = require "coq.lib.test"
local async = require "coq.lib.async"
local deadline = require "coq.lib.async.deadline"

---@param items any[]
---@return lib.Iterator<any>
local from = function(items)
  local i = 0
  return function()
    i = i + 1
    return items[i]
  end
end

---@param iter lib.Iterator<any>
---@return any[]
local drain = function(iter)
  local out = {}
  for v in iter do
    table.insert(out, v)
  end
  return out
end

T.describe("deadline", function(test)
  test("nil timeout returns the iter as-is", function()
    local iter = deadline.new(nil, from { "spot", "fido" })
    T.eq(drain(iter), { "spot", "fido" })
  end)

  test("zero timeout returns the iter as-is", function()
    local iter = deadline.new(0, from { "spot", "fido" })
    T.eq(drain(iter), { "spot", "fido" })
  end)

  test("negative timeout returns the iter as-is", function()
    local iter = deadline.new(-5, from { "spot" })
    T.eq(drain(iter), { "spot" })
  end)

  test("forwards values when iter finishes before the deadline", function()
    local iter = deadline.new(200 * T.SLOW, from { "spot", "fido", "rex" })
    T.eq(drain(iter), { "spot", "fido", "rex" })
  end)

  test("returns nil after the deadline, preserves what was pulled before it", function()
    local pulled = 0
    local slow = function()
      pulled = pulled + 1
      if pulled == 1 then
        return "spot"
      end
      if pulled == 2 then
        return "fido"
      end
      async.sleep(500 * T.SLOW)
      return "labrador"
    end
    T.eq(drain(deadline.new(20 * T.SLOW, slow)), { "spot", "fido" })
  end)

  test("latches after the first nil — subsequent calls return nil without re-racing", function()
    local pulled = 0
    local slow = function()
      pulled = pulled + 1
      async.sleep(500 * T.SLOW)
      return "labrador"
    end
    local iter = deadline.new(10 * T.SLOW, slow)
    T.eq(iter(), nil)
    local before = pulled
    T.eq(iter(), nil)
    T.eq(iter(), nil)
    T.eq(pulled, before)
  end)

  test("does not block beyond the deadline when iter is slow", function()
    local iter = deadline.new(10 * T.SLOW, function()
      async.sleep(500 * T.SLOW)
      return "labrador"
    end)
    local start = vim.uv.hrtime()
    iter()
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    assert(elapsed_ms < 200 * T.SLOW, ("expected ~10ms, got %.1fms"):format(elapsed_ms))
  end)

  test("natural nil from the iter also latches future calls", function()
    local pulled = 0
    local iter = deadline.new(200 * T.SLOW, function()
      pulled = pulled + 1
      if pulled == 1 then
        return "spot"
      end
      return nil
    end)
    T.eq(iter(), "spot")
    T.eq(iter(), nil)
    local before = pulled
    T.eq(iter(), nil)
    T.eq(pulled, before)
  end)
end)
