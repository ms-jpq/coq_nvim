local M = {}

---@param buf integer
---@return integer
M.buf_size = function(buf)
  return vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
end

---@param buf integer
---@return integer lo
---@return integer hi
M.window_around_cursor = function(buf)
  assert(not vim.in_fast_event(), debug.traceback("coq: window_around_cursor in fast event context", 2))

  local count = vim.api.nvim_buf_line_count(buf)
  local win = vim.fn.bufwinid(buf)
  local row = win == -1 and 0 or (unpack(vim.api.nvim_win_get_cursor(win)) - 1)
  local height = vim.o.lines

  local lo, hi = row - height, row + height + 1
  if lo < 0 then
    hi = hi - lo
  end
  if hi > count then
    lo = lo - (hi - count)
  end

  return math.max(0, lo), math.min(count, hi)
end

---@param buf integer
---@return string[]
M.lines_around_cursor = function(buf)
  local lo, hi = M.window_around_cursor(buf)
  return vim.api.nvim_buf_get_lines(buf, lo, hi, true)
end

return M
