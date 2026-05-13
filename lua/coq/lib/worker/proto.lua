-- Wire protocol for worker IPC: 4-byte LE length prefix + mpack body.

local encode = function(body)
  local payload = vim.mpack.encode(body)
  local n = #payload
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    .. payload
end

local consume = function(buf, on_frame)
  local pos = 1
  while pos + 3 <= #buf do
    local b1, b2, b3, b4 = buf:byte(pos, pos + 3)
    local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    if pos + 3 + n > #buf then
      break
    end
    on_frame(vim.mpack.decode(buf:sub(pos + 4, pos + 3 + n)))
    pos = pos + 4 + n
  end
  return buf:sub(pos)
end

local pack = function(ok, ...)
  return ok, select("#", ...), { ... }
end

return { encode = encode, consume = consume, pack = pack }
