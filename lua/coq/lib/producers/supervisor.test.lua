local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local producer = require "coq.lib.producers"
local supervisor = require "coq.lib.producers.supervisor"

---@return async.Nursery
local detached = function()
  local n = nursery.new()
  local _ = handle.new().on_cancel(n.cancel)
  return n
end

---@param matcher producers.MatcherFn
---@return producers.Producer
local matcher_only = function(matcher)
  return producer.new { idle = lib.noop, bind = lib.noop, matcher = matcher }
end

---@param ... any
---@return producers.Producer
local yields = function(...)
  local items = { ... }
  return matcher_only(function()
    for _, v in ipairs(items) do
      coroutine.yield(v)
    end
  end)
end

---@param fields { idle?: producers.IdleFn, matcher?: producers.MatcherFn }
---@return producers.Producer, fun(ev: any)
local pushable = function(fields)
  local push
  local p = producer.new {
    idle = fields.idle or lib.noop,
    matcher = fields.matcher or lib.noop,
    bind = function(_, p_push)
      push = p_push
    end,
  }
  return p, function(ev)
    push(ev)
  end
end

---@param iter producers.SearchIter
local drain = function(iter)
  for _ in iter do
    lib.noop()
  end
end

T.describe("supervisor", function(test)
  test("merges rows from all producers", function()
    local n = detached()
    local sup = supervisor.new { yields("lil", "spot"), yields "fido" }
    sup.bind(n)
    local seen = {}
    for row in sup.search {} do
      table.insert(seen, row)
    end
    n.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)

  test("idle runs once search has ended", function()
    local idle_ran = async.future()
    async.scope(function(n)
      local p, push = pushable {
        idle = function()
          idle_ran.resolve()
        end,
        matcher = function()
          coroutine.yield "lil"
        end,
      }
      local sup = supervisor.new { p }
      sup.bind(n)
      push(true)
      drain(sup.search {})
      sup.idle {}
      idle_ran.await()
    end)
  end)

  test("producer error kills the merged stream", function()
    local n = detached()
    local sup = supervisor.new {
      matcher_only(function()
        coroutine.yield "lil"
        error "boom"
      end),
    }
    sup.bind(n)
    local ok, err = pcall(function()
      drain(sup.search {})
    end)
    n.cancel()

    T.eq(ok, false)
    assert(err and tostring(err):find "boom", "expected 'boom', got: " .. tostring(err))
  end)

  test("bind cascades to each producer once, even on repeat cancel", function()
    local cleanups = {}
    local trace = function(name)
      return producer.new {
        idle = lib.noop,
        matcher = lib.noop,
        bind = function(n)
          local _ = n.on_cancel(function()
            cleanups[name] = (cleanups[name] or 0) + 1
          end)
        end,
      }
    end
    local n = detached()
    local sup = supervisor.new { trace "a", trace "b" }
    sup.bind(n)
    n.cancel()
    n.cancel()

    T.eq(cleanups, { a = 1, b = 1 })
  end)

  test("iter.close from a sibling coroutine cancels the matcher", function()
    local matcher_cancelled = async.future()
    local matcher_sleeping = async.future()
    local first
    async.scope(function(n)
      local sup = supervisor.new {
        matcher_only(function()
          coroutine.yield "lil"
          matcher_sleeping.resolve()
          local ok = pcall(async.sleep, 100 * T.SLOW)
          matcher_cancelled.resolve(not ok)
        end),
      }
      sup.bind(n)
      async.scope(function(inner)
        local iter = sup.search {}
        inner.spawn(function()
          first = iter()
          pcall(iter --[[@as fun()]])
        end)
        matcher_sleeping.await()
        iter.close()
        matcher_cancelled.await()
      end)
    end)

    T.eq(first, "lil")
  end)

  test("supervisor satisfies the Producer shape (nestable)", function()
    local n = detached()
    local inner = supervisor.new { yields "lil", yields "spot" }
    local outer = supervisor.new { inner, yields "fido" }
    outer.bind(n)
    local seen = {}
    for row in outer.search {} do
      table.insert(seen, row)
    end
    n.cancel()

    table.sort(seen)
    T.eq(seen, { "fido", "lil", "spot" })
  end)
end)
