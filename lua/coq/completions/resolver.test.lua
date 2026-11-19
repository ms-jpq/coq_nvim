local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local resolver_m = require "coq.completions.resolver"
local timelord_m = require "coq.completions.timelord"

local LORD = timelord_m.new()

---@type ctx.base
local CTX = { win = 0, buf = 0, pos = { 0, 0 }, line = "", changedtick = 0, filetype = "" }

---@return completions.Item
local lsp_item = function(tag)
  return {
    word = tag,
    meta = { uid = tag, source = "LSP", filter = { tag }, fuzzy = 0, lsp = { tag = tag } },
  } --[[@as completions.Item]]
end

T.describe({ "resolver" }, function(test)
  test({ "caches resolved results by uid" }, function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, LORD, function(_, meta)
        calls = calls + 1
        return meta.lsp
      end)
      local item = lsp_item "fido"
      local a = r.resolve(CTX, item.meta)
      local b = r.resolve(CTX, item.meta)
      T.eq(a, item.meta.lsp)
      T.eq(b, item.meta.lsp)
    end)
    T.eq(calls, 1)
  end)

  test({ "shares cache across distinct tables of equal content" }, function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, LORD, function(_, meta)
        calls = calls + 1
        return meta.lsp
      end)
      local highlight_copy = lsp_item "fido"
      local commit_copy = lsp_item "fido"
      assert(highlight_copy ~= commit_copy, "fixture must use distinct tables")
      r.resolve(CTX, highlight_copy.meta)
      r.resolve(CTX, commit_copy.meta)
    end)
    T.eq(calls, 1)
  end)

  test({ "dedups concurrent in-flight requests" }, function()
    local calls = 0
    local got = {}
    async.scope(function(n)
      local gate = async.future()
      local started = async.future()
      local r = resolver_m.new(n, LORD, function(_, meta)
        calls = calls + 1
        started.resolve()
        gate.await()
        return meta.lsp
      end)
      local item = lsp_item "spot"

      n.spawn(function()
        got.a = r.resolve(CTX, item.meta)
      end)
      n.spawn(function()
        got.b = r.resolve(CTX, item.meta)
      end)

      started.await()
      gate.resolve()
    end)

    T.eq(calls, 1)
    assert(got.a ~= nil and got.a == got.b, "both awaiters should share the resolved value")
  end)

  test({ "reset clears state and re-fetches" }, function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, LORD, function(_, meta)
        calls = calls + 1
        return meta.lsp
      end)
      local item = lsp_item "lil"
      r.resolve(CTX, item.meta)
      r.reset()
      r.resolve(CTX, item.meta)
    end)
    T.eq(calls, 2)
  end)

  test({ "a stale cycle's failed fetch does not evict the new cycle's entry" }, function()
    local calls = 0
    async.scope(function(n)
      local started = async.future()
      local release = async.future()
      local hold = true
      local r = resolver_m.new(n, LORD, function(_, meta)
        calls = calls + 1
        if hold then
          hold = false
          started.resolve()
          release.await()
          error(cancel.new(), 0)
        end
        return meta.lsp
      end)
      local item = lsp_item "fido"

      n.spawn(function()
        r.resolve(CTX, item.meta)
      end)
      started.await()

      r.reset()
      r.resolve(CTX, item.meta)

      release.resolve()

      r.resolve(CTX, item.meta)
    end)
    T.eq(calls, 2)
  end)

  test({ "caches a nil result without re-fetching" }, function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, LORD, function()
        calls = calls + 1
        return nil
      end)
      local item = { word = "rex", meta = { uid = "rex", source = "BF", filter = { "rex" }, fuzzy = 0 } } --[[@as completions.Item]]
      T.eq(r.resolve(CTX, item.meta), nil)
      T.eq(r.resolve(CTX, item.meta), nil)
    end)
    T.eq(calls, 1)
  end)
end)
