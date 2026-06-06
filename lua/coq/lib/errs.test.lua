local T = require "coq.lib.test"
local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"

T.describe({ "errs.group" }, function(test)
  test({ "collects the errors and renders them" }, function()
    local g = errs.group { "spot", "fido" }
    T.eq(g.errs, { "spot", "fido" })

    local rendered = tostring(g)
    assert(rendered:find "error group %(2 errors%)", "expected header, got: " .. rendered)
    assert(rendered:find "spot" and rendered:find "fido", "expected entries, got: " .. rendered)
  end)
end)

T.describe({ "errs.raise" }, function(test)
  test({ "an empty list does not raise" }, function()
    T.eq(pcall(errs.check_raise, {}), true)
  end)

  test({ "a single error is raised unchanged" }, function()
    local boom = { breed = "labrador" }
    local ok, err = pcall(errs.check_raise, { boom })
    T.eq(ok, false)
    T.eq(err, boom)
  end)

  test({ "several errors raise a group holding all of them" }, function()
    local ok, err = pcall(errs.check_raise, { "spot", "fido" })
    T.eq(ok, false)
    ---@cast err lib.ErrorGroup<string>
    T.eq(err.errs, { "spot", "fido" })
  end)

  test({ "all-cancellation errors propagate the first cancel, not a group" }, function()
    local first, second = cancel.new(), cancel.new()
    local ok, err = pcall(errs.check_raise, { first, second })
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
    T.eq(err, first)
  end)

  test({ "a single real error among cancellations is raised alone" }, function()
    local ok, err = pcall(errs.check_raise, { cancel.new(), "real" })
    T.eq(ok, false)
    T.eq(cancel.is(err), false)
    T.eq(err, "real")
  end)

  test({ "multiple real errors among cancellations group only the real ones" }, function()
    local ok, err = pcall(errs.check_raise, { cancel.new(), "real1", cancel.new(), "real2" })
    T.eq(ok, false)
    T.eq(cancel.is(err), false)
    ---@cast err lib.ErrorGroup<any>
    T.eq(#err.errs, 2)
    T.eq(err.errs[1], "real1")
    T.eq(err.errs[2], "real2")
  end)
end)

T.describe({ "errs.with_reporting" }, function(test)
  test({ "a cancellation is re-raised, not reported" }, function()
    local guarded = errs.with_reporting(function()
      error(cancel.new(), 0)
    end)
    local ok, err = pcall(guarded)
    T.eq(ok, false)
    T.eq(cancel.is(err), true)
  end)

  test({ "a normal return passes through" }, function()
    local guarded = errs.with_reporting(function()
      return "spot"
    end)
    T.eq(pcall(guarded), true)
  end)
end)
