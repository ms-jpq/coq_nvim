local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local nursery = require "coq.lib.async.nursery"

T.describe("cancel sentinel", function(test)
  test("is identifies cancel errors", function()
    T.eq(cancel.is(cancel.new()), true)
  end)

  test("is rejects non-cancel values", function()
    T.eq(cancel.is {}, false)
    T.eq(cancel.is "cancelled", false)
    T.eq(cancel.is(nil), false)
    T.eq(cancel.is(setmetatable({}, {})), false)
  end)

  test("cancel error has readable __tostring", function()
    T.eq(tostring(cancel.new()), "<cancelled>")
  end)
end)

T.describe("cancel by throw", function(test)
  test("nursery does not record cancel in its error list", function()
    local n = nursery.new()
    n.spawn(function()
      n.handle.cancel()
      async.sleep(50 * T.SLOW)
    end)

    local ok, err = pcall(n.join)
    T.eq(ok, true)
    T.eq(err, nil)
  end)
end)

T.describe("cancel.pcall", function(test)
  test("passes cancel through as if not caught", function()
    local ok, err = pcall(function()
      cancel.pcall(function()
        error(cancel.new(), 0)
      end)
    end)
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
  end)

  test("catches non-cancel errors normally", function()
    local ok, err = cancel.pcall(function()
      error("bad dog", 0)
    end)
    T.eq(ok, false)
    T.eq(err, "bad dog")
  end)

  test("returns multiple values on success", function()
    local ok, a, b, c = cancel.pcall(function()
      return "lil", "spot", "fido"
    end)
    T.eq({ ok, a, b, c }, { true, "lil", "spot", "fido" })
  end)

  test("forwards args to fn", function()
    local ok, sum = cancel.pcall(function(a, b)
      return a + b
    end, 3, 4)
    T.eq({ ok, sum }, { true, 7 })
  end)
end)

T.describe("cancel.xpcall", function(test)
  test("passes cancel through without invoking handler", function()
    local handler_called = false
    local ok, err = pcall(function()
      cancel.xpcall(function()
        error(cancel.new(), 0)
      end, function(e)
        handler_called = true
        return e
      end)
    end)
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
    T.eq(handler_called, false)
  end)

  test("invokes handler for non-cancel errors", function()
    local ok, err = cancel.xpcall(function()
      error("bad dog", 0)
    end, function(e)
      return "wrapped: " .. tostring(e)
    end)
    T.eq(ok, false)
    T.eq(err, "wrapped: bad dog")
  end)
end)
