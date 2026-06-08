local M = {}

---@class lib.DebugScope
---@field enabled boolean
---@field notify fun(msg: string)
---@field buf fun(buf: integer, tag: string)

---@param name string
---@return lib.DebugScope
M.scope = function(name)
  local enabled = os.getenv("COQ_DEBUG_" .. name) ~= nil

  local notify = function(msg)
    if enabled then
      vim.notify("[coq:" .. name .. "] " .. msg)
    end
  end

  local buf = function(buf, tag)
    if not enabled then
      return
    end
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line_count = vim.api.nvim_buf_line_count(buf)
    local from = math.max(0, row - 3)
    local to = math.min(line_count, row + 2)
    local lines = vim.api.nvim_buf_get_lines(buf, from, to, false)
    local out = {}
    for k, l in ipairs(lines) do
      local n = from + k
      table.insert(out, ("%s%4d │ %s"):format(n == row and ">" or " ", n, l))
    end
    vim.notify(("[coq:%s] %s — cursor=(%d,%d)\n%s"):format(name, tag, row, col, table.concat(out, "\n")))
  end

  return { enabled = enabled, notify = notify, buf = buf }
end

return M
