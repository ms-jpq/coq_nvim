-- Worker IPC wire protocol: 4-byte LE length prefix + mpack body.

local HEADER_SIZE = 4
local BYTE = 256

local M = {}

---@param body table
---@return string
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

---@return fun(data: string): fun(): table?
M.decoder = function()
  local buf, pos = "", 1

  return function(data)
    if pos > 1 then
      buf = buf:sub(pos)
      pos = 1
    end
    buf = buf .. data

    return function()
      local avail = #buf - pos + 1
      if avail < HEADER_SIZE then
        return nil
      end

      local b1, b2, b3, b4 = buf:byte(pos, pos + HEADER_SIZE - 1)
      local n = b1 + b2 * BYTE + b3 * BYTE * BYTE + b4 * BYTE * BYTE * BYTE
      if avail < HEADER_SIZE + n then
        return nil
      end

      local body = buf:sub(pos + HEADER_SIZE, pos + HEADER_SIZE + n - 1)
      pos = pos + HEADER_SIZE + n
      return vim.mpack.decode(body)
    end
  end
end

return M
