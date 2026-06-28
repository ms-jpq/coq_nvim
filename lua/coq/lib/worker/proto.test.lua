local T = require "coq.lib.test"
local proto = require "coq.lib.worker.wire_proto"

local drain = function(decode, data)
  local seen = {}
  for frame in decode(data) do
    table.insert(seen, frame)
  end
  return seen
end

T.describe({ "proto" }, function(test)
  test({ "encode + decode round-trips a frame" }, function()
    local body = { kind = "request", id = 7, method = "bark", args = { "lil" } }
    local seen = drain(proto.decoder(), proto.encode(body))

    T.eq(#seen, 1)
    T.eq(seen[1], body)
  end)

  test({ "decoder handles two frames in one feed" }, function()
    local a = proto.encode { kind = "x", id = 1 }
    local b = proto.encode { kind = "y", id = 2 }
    local seen = drain(proto.decoder(), a .. b)

    T.eq({ seen[1].kind, seen[2].kind }, { "x", "y" })
  end)

  test({ "decoder buffers an incomplete frame across feeds" }, function()
    local frame = proto.encode { kind = "x", id = 1 }
    local decode = proto.decoder()

    local first = drain(decode, string.sub(frame, 1, #frame - 3))
    T.eq(first, {})

    local rest = drain(decode, string.sub(frame, #frame - 2))
    T.eq(#rest, 1)
    T.eq(rest[1].kind, "x")
  end)

  test({ "decoder buffers a header-only feed" }, function()
    local frame = proto.encode { kind = "x", id = 1 }
    local decode = proto.decoder()

    local first = drain(decode, string.sub(frame, 1, 4))
    T.eq(first, {})

    local rest = drain(decode, string.sub(frame, 5))
    T.eq(#rest, 1)
  end)

  test({ "decoder on an empty feed yields nothing" }, function()
    T.eq(drain(proto.decoder(), ""), {})
  end)

  test({ "encode handles a payload larger than one byte length" }, function()
    local big = string.rep("lil", 500)
    local seen = drain(proto.decoder(), proto.encode { kind = "x", payload = big })

    T.eq(seen[1].payload, big)
  end)
end)
