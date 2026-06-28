-- Worker IPC wire protocol: newline-delimited JSON.

local json = require "coq.lib.json"

local M = {}

---@param body table
---@return string
M.encode = function(body)
  return vim.json.encode(body) .. "\n"
end

---@return fun(data: string): fun(): table?
M.decoder = function()
  local buf = ""

  return function(data)
    buf = buf .. data

    return function()
      local nl = string.find(buf, "\n", 1, true)
      if not nl then
        return nil
      end
      local line = string.sub(buf, 1, nl - 1)
      buf = string.sub(buf, nl + 1)
      return vim.json.decode(line, json.DECODE_OPTS)
    end
  end
end

return M
