local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local trigger = require "coq.completions.trigger"

---@param overrides? table
---@return ctx.full
local mk_ctx = function(overrides)
  return TH.ctx_of(vim.tbl_extend("force", {
    buf = 1,
    changedtick = 7,
    pos = { 3, 5, 5, 5 },
    line_before = "fido(",
  }, overrides or {}))
end

---@param overrides? table
---@return config.Settings
local mk_settings = function(overrides)
  ---@diagnostic disable-next-line: missing-fields
  local s = {
    completion = {
      always = true,
      sticky_manual = false,
      skip_after = {},
    },
  }
  return vim.tbl_deep_extend("force", s, overrides or {}) --[[@as config.Settings]]
end

T.describe({ "trigger._dedup_key" }, function(test)
  test({ "formats buf:tick:row:col" }, function()
    T.eq(trigger._dedup_key(mk_ctx()), "1:7:3:5")
  end)

  test({ "different ticks differ" }, function()
    T.eq(trigger._dedup_key(mk_ctx { changedtick = 7 }) == trigger._dedup_key(mk_ctx { changedtick = 8 }), false)
  end)

  test({ "different cursors differ at same tick" }, function()
    T.eq(
      trigger._dedup_key(mk_ctx { pos = { 3, 5, 5, 5 } }) == trigger._dedup_key(mk_ctx { pos = { 3, 6, 6, 6 } }),
      false
    )
  end)

  test({ "same buf+tick+pos collide" }, function()
    T.eq(trigger._dedup_key(mk_ctx()), trigger._dedup_key(mk_ctx()))
  end)
end)

T.describe({ "trigger._should_skip" }, function(test)
  test({ "manual triggers always proceed" }, function()
    local s = mk_settings { completion = { always = false } }
    T.eq(trigger._should_skip(s, mk_ctx { manual = true }, ""), false)
  end)

  test({ "auto trigger skipped when always=false" }, function()
    local s = mk_settings { completion = { always = false } }
    T.eq(trigger._should_skip(s, mk_ctx { manual = false }, ""), true)
  end)

  test({ "dedup key match skips the second trigger" }, function()
    local s = mk_settings()
    local ctx = mk_ctx()
    local prev = trigger._dedup_key(ctx)
    T.eq(trigger._should_skip(s, ctx, prev), true)
  end)

  test({ "manual overrides dedup key" }, function()
    local s = mk_settings()
    local ctx = mk_ctx { manual = true }
    local prev = trigger._dedup_key(ctx)
    T.eq(trigger._should_skip(s, ctx, prev), false)
  end)

  test({ "passes through when no skip rules apply" }, function()
    T.eq(trigger._should_skip(mk_settings(), mk_ctx(), ""), false)
  end)
end)

T.describe({ "trigger._should_skip :: skip_after literal" }, function(test)
  test({ "line ending in a configured suffix is skipped" }, function()
    local s = mk_settings { completion = { skip_after = { "(" } } }
    T.eq(trigger._should_skip(s, mk_ctx { line_before = "fido(" }, ""), true)
  end)

  test({ "line not ending in suffix passes" }, function()
    local s = mk_settings { completion = { skip_after = { "(" } } }
    T.eq(trigger._should_skip(s, mk_ctx { line_before = "fido" }, ""), false)
  end)

  test({ "empty-string suffix is ignored (would otherwise match everything)" }, function()
    local s = mk_settings { completion = { skip_after = { "" } } }
    T.eq(trigger._should_skip(s, mk_ctx { line_before = "fido" }, ""), false)
  end)

  test({ "multi-char suffix matched by tail" }, function()
    local s = mk_settings { completion = { skip_after = { "::" } } }
    T.eq(trigger._should_skip(s, mk_ctx { line_before = "std::" }, ""), true)
    T.eq(trigger._should_skip(s, mk_ctx { line_before = "std:" }, ""), false)
  end)

  test({ "any matching suffix triggers skip" }, function()
    local s = mk_settings { completion = { skip_after = { ",", "(", ";" } } }
    T.eq(trigger._should_skip(s, mk_ctx { line_before = "x;" }, ""), true)
  end)
end)

T.describe({ "trigger._should_skip :: skip_after newline" }, function(test)
  test({ "\\n suffix skips blank-line context past row 1" }, function()
    local s = mk_settings { completion = { skip_after = { "\n" } } }
    T.eq(trigger._should_skip(s, mk_ctx { pos = { 3, 0, 0, 0 }, line_before = "  " }, ""), true)
  end)

  test({ "\\n suffix does NOT skip on row 1 (no preceding newline)" }, function()
    local s = mk_settings { completion = { skip_after = { "\n" } } }
    T.eq(trigger._should_skip(s, mk_ctx { pos = { 1, 0, 0, 0 }, line_before = "  " }, ""), false)
  end)

  test({ "\\n suffix does NOT skip on a non-blank line" }, function()
    local s = mk_settings { completion = { skip_after = { "\n" } } }
    T.eq(trigger._should_skip(s, mk_ctx { pos = { 3, 4, 4, 4 }, line_before = "fido" }, ""), false)
  end)

  test({ "\\r\\n suffix obeys the same blank-line rule" }, function()
    local s = mk_settings { completion = { skip_after = { "\r\n" } } }
    T.eq(trigger._should_skip(s, mk_ctx { pos = { 3, 0, 0, 0 }, line_before = "" }, ""), true)
  end)
end)
