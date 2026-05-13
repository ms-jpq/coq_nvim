-- Wire protocol for worker IPC: 4-byte LE length prefix + mpack body.

local HEADER_SIZE = 4
local BYTE = 256

local M = {}

M.KIND = {
  REQUEST = "request",
  RESPONSE = "response",
  MAIN_CALL = "main_call",
  MAIN_RESPONSE = "main_response",
  YIELD = "yield",
  NEXT = "next",
  STOP = "stop",
}

M.MODE = {
  STREAM = "stream",
  RPC = "rpc",
}

M.encode = function(body)
  local payload = vim.mpack.encode(body)
  local n = #payload
  return string.char(
    n % BYTE,
    math.floor(n / BYTE) % BYTE,
    math.floor(n / (BYTE * BYTE)) % BYTE,
    math.floor(n / (BYTE * BYTE * BYTE)) % BYTE
  ) .. payload
end

local decode = function(buf)
  if #buf < HEADER_SIZE then
    return nil
  end
  local b1, b2, b3, b4 = buf:byte(1, HEADER_SIZE)
  local n = b1 + b2 * BYTE + b3 * BYTE * BYTE + b4 * BYTE * BYTE * BYTE
  if #buf < HEADER_SIZE + n then
    return nil
  end
  local decoded = vim.mpack.decode(buf:sub(HEADER_SIZE + 1, HEADER_SIZE + n))
  return decoded, buf:sub(HEADER_SIZE + n + 1)
end

M.consume = function(buf)
  local iter = coroutine.wrap(function()
    while true do
      local frame, rest = decode(buf)
      if not frame then
        return
      end
      coroutine.yield(frame)
      buf = rest
    end
  end)

  return iter, function()
    return buf
  end
end

M.pack = function(ok, ...)
  return ok, select("#", ...), { ... }
end

M.start_reader = function(pipe, handlers, on_eof)
  local buf = ""
  pipe:read_start(function(err, data)
    if err or not data then
      pipe:close()
      on_eof()
      return
    end
    local iter, leftover = M.consume(buf .. data)
    for frame in iter do
      handlers[frame.kind](frame)
    end
    buf = leftover()
  end)
end

M.unwrap = function(err, ...)
  if err then
    error(err, 3)
  end
  return ...
end

return M
