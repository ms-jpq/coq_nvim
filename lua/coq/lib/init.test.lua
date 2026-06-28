local T = require "coq.lib.test"
local cancel = require "coq.lib.async.cancel"
local lib = require "coq.lib"

T.describe({ "lib.scope" }, function(test)
  test({ "returns the body's values" }, function()
    local a, b = lib.scope(function()
      return "spot", 3
    end)
    T.eq(a, "spot")
    T.eq(b, 3)
  end)

  test({ "runs defers in reverse order, after the body" }, function()
    local order = {}
    lib.scope(function(defer)
      defer(function()
        table.insert(order, "first")
      end)
      defer(function()
        table.insert(order, "second")
      end)
      table.insert(order, "body")
    end)
    T.eq(order, { "body", "second", "first" })
  end)

  test({ "runs defers even when the body raises, then re-raises the body error" }, function()
    local cleaned = false
    local ok, err = pcall(lib.scope, function(defer)
      defer(function()
        cleaned = true
      end)
      error("lil went missing", 0)
    end)
    T.eq(ok, false)
    T.eq(err, "lil went missing")
    T.eq(cleaned, true)
  end)

  test({ "a failing defer is raised, not swallowed" }, function()
    local ok, err = pcall(lib.scope, function(defer)
      defer(function()
        error("defer boom", 0)
      end)
    end)
    T.eq(ok, false)
    assert(tostring(err):find "defer boom", "expected defer error, got: " .. tostring(err))
  end)

  test({ "body error and defer error surface together as a group" }, function()
    local ok, err = pcall(lib.scope, function(defer)
      defer(function()
        error("cleanup failed", 0)
      end)
      error("body failed", 0)
    end)
    T.eq(ok, false)
    T.eq(#err.errs, 2)
  end)

  test({ "a cancelled body with clean defers propagates the cancel" }, function()
    local cleaned = false
    local ok, err = pcall(lib.scope, function(defer)
      defer(function()
        cleaned = true
      end)
      error(cancel.new(), 0)
    end)
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
    T.eq(cleaned, true)
  end)
end)
