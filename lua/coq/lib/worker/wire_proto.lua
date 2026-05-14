-- Worker IPC wire protocol: 4-byte LE length prefix + mpack body.

local HEADER_SIZE = 4
local BYTE = 256

local M = {}

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
    return nil, ""
  end
  local b1, b2, b3, b4 = buf:byte(1, HEADER_SIZE)
  local n = b1 + b2 * BYTE + b3 * BYTE * BYTE + b4 * BYTE * BYTE * BYTE
  if #buf < HEADER_SIZE + n then
    return nil, ""
  end

  local decoded = vim.mpack.decode(buf:sub(HEADER_SIZE + 1, HEADER_SIZE + n))
  return decoded, buf:sub(HEADER_SIZE + n + 1)
end

M.decoder = function()
  local buf = ""

  return function(data)
    buf = buf .. data

    return function()
      local frame, rest = decode(buf)
      if not frame then
        return nil
      end

      buf = rest
      return frame
    end
  end
end

return M
