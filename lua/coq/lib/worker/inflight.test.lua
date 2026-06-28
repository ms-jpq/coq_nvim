local T = require "coq.lib.test"
local inflight = require "coq.lib.worker.inflight"

T.describe({ "inflight" }, function(test)
  test({ "reserve assigns sequential ids and invokes the cb on resolve" }, function()
    local p = inflight.new()
    local got
    local id, _ = p.reserve(function(msg)
      got = msg
    end)
    T.eq(id, 1)
    p.resolve(id, "fido")
    T.eq(got, "fido")
  end)

  test({ "explicit id takes precedence over sequential" }, function()
    local p = inflight.new()
    local id, _ = p.reserve(function() end, 42)
    T.eq(id, 42)
  end)

  test({ "resolve on an unknown id is a no-op" }, function()
    local p = inflight.new()
    p.resolve(99, "ghost") -- must not throw
  end)

  test({ "concurrent ids don't collide and resolve independently" }, function()
    local p = inflight.new()
    local seen = {}
    local id_a = p.reserve(function(m)
      seen.a = m
    end)
    local id_b = p.reserve(function(m)
      seen.b = m
    end)
    assert(id_a ~= id_b, "ids must be distinct")
    p.resolve(id_b, "spot")
    T.eq(seen, { b = "spot" })
    p.resolve(id_a, "lil")
    T.eq(seen, { a = "lil", b = "spot" })
  end)

  test({ "id collision raises" }, function()
    local p = inflight.new()
    p.reserve(function() end, 7)
    local ok, err = pcall(p.reserve, function() end, 7)
    T.eq(ok, false)
    assert(tostring(err):find "id collision 7")
  end)

  test({ "has reports presence; unwatch removes the entry" }, function()
    local p = inflight.new()
    local id, unwatch = p.reserve(function() end)
    T.eq(p.has(id), true)
    unwatch()
    T.eq(p.has(id), false)
    -- subsequent resolve is a no-op (cb is gone)
    p.resolve(id, "anything")
  end)

  test({ "drain fires every pending cb once and clears the map" }, function()
    local p = inflight.new()
    local got = {}
    p.reserve(function(m)
      table.insert(got, m)
    end)
    p.reserve(function(m)
      table.insert(got, m)
    end)
    p.drain "shutdown"
    table.sort(got)
    T.eq(got, { "shutdown", "shutdown" })
    -- After drain the entries are gone.
    T.eq(p.has(1), false)
    T.eq(p.has(2), false)
  end)

  test({ "cb reserved during drain is not lost (drain snapshots first)" }, function()
    local p = inflight.new()
    p.reserve(function()
      -- This callback fires during drain. Reserving inside it must not
      -- be visited by the same drain pass — the new entry survives.
      p.reserve(function() end, 100)
    end)
    p.drain "tick"
    T.eq(p.has(100), true)
  end)
end)
