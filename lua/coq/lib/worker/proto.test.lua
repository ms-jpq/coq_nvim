local T = require "coq.lib.test"
local proto = require "coq.lib.worker.proto"

local drain = function(buf)
  local iter, leftover = proto.consume(buf)
  local seen = {}
  for frame in iter do
    table.insert(seen, frame)
  end
  return seen, leftover()
end

T.describe("proto", function(test)
  test("encode + consume round-trips a frame", function()
    local body = { kind = "request", id = 7, method = "bark", args = { "lil" } }
    local seen, rest = drain(proto.encode(body))

    T.eq(#seen, 1)
    T.eq(seen[1], body)
    T.eq(rest, "")
  end)

  test("consume handles two frames in one buffer", function()
    local a = proto.encode { kind = "x", id = 1 }
    local b = proto.encode { kind = "y", id = 2 }
    local seen, rest = drain(a .. b)

    T.eq({ seen[1].kind, seen[2].kind }, { "x", "y" })
    T.eq(rest, "")
  end)

  test("consume returns leftover bytes for incomplete frame", function()
    local frame = proto.encode { kind = "x", id = 1 }
    local truncated = frame:sub(1, #frame - 3)
    local seen, rest = drain(truncated)

    T.eq(seen, {})
    T.eq(rest, truncated)
  end)

  test("consume returns leftover when only header is present", function()
    local frame = proto.encode { kind = "x", id = 1 }
    local just_header = frame:sub(1, 4)
    local seen, rest = drain(just_header)

    T.eq(seen, {})
    T.eq(rest, just_header)
  end)

  test("consume on empty buffer is a noop", function()
    local seen, rest = drain ""

    T.eq(seen, {})
    T.eq(rest, "")
  end)

  test("encode handles a payload larger than one byte length", function()
    local big = string.rep("lil", 500)
    local seen = drain(proto.encode { kind = "x", payload = big })

    T.eq(seen[1].payload, big)
  end)

  test("pack captures ok, arity, and values", function()
    local ok, n, vals = proto.pack(true, "lil", "spot", "fido")

    T.eq(ok, true)
    T.eq(n, 3)
    T.eq(vals, { "lil", "spot", "fido" })
  end)

  test("pack captures error path", function()
    local ok, n, vals = proto.pack(false, "leash snapped")

    T.eq(ok, false)
    T.eq(n, 1)
    T.eq(vals, { "leash snapped" })
  end)

  test("pack records arity including trailing nils", function()
    local ok, n, vals = proto.pack(true, "lil", nil, "fido")

    T.eq(ok, true)
    T.eq(n, 3)
    T.eq(vals[1], "lil")
    T.eq(vals[2], nil)
    T.eq(vals[3], "fido")
  end)

  test("unwrap returns rest when err is nil", function()
    local a, b, c = proto.unwrap(nil, "lil", "spot", "fido")

    T.eq(a, "lil")
    T.eq(b, "spot")
    T.eq(c, "fido")
  end)

  test("unwrap raises when err is set", function()
    local ok, err = pcall(proto.unwrap, "lil went missing")

    T.eq(ok, false)
    assert(err:find "lil went missing", "expected error message, got: " .. tostring(err))
  end)
end)
