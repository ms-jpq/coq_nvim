local T = require "coq.lib.test"
local ring = require "coq.lib.ring"

---@param items any[]
---@return any[]
local sorted = function(items)
  local out = {}
  for i, v in ipairs(items) do
    out[i] = v
  end
  table.sort(out)
  return out
end

T.describe({ "ring" }, function(test)
  test({ "len grows until capacity, then stays" }, function()
    local r = ring.new(3)
    T.eq(r.len(), 0)
    r.push "lil"
    T.eq(r.len(), 1)
    r.push "spot"
    r.push "fido"
    T.eq(r.len(), 3)
    r.push "rex"
    T.eq(r.len(), 3)
  end)

  test({ "items returns current contents (order-independent)" }, function()
    local r = ring.new(3)
    r.push "lil"
    r.push "spot"
    r.push "fido"
    T.eq(sorted(r.items()), { "fido", "lil", "spot" })
  end)

  test({ "push overwrites oldest once at capacity" }, function()
    local r = ring.new(3)
    r.push "lil"
    r.push "spot"
    r.push "fido"
    r.push "rex" -- evicts "lil"
    T.eq(sorted(r.items()), { "fido", "rex", "spot" })
  end)

  test({ "items returns a fresh copy — safe to sort without affecting the ring" }, function()
    local r = ring.new(3)
    r.push(3)
    r.push(1)
    r.push(2)
    local snapshot = r.items()
    table.sort(snapshot)
    T.eq(snapshot, { 1, 2, 3 })

    -- ring is unaffected by the sort above
    r.push(0)
    T.eq(sorted(r.items()), { 0, 1, 2 })
  end)
end)
