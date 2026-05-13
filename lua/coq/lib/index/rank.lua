local M = {}

M.window = function(ctx)
  local half = math.floor(vim.api.nvim_win_get_height(ctx.win) / 2)
  local row = ctx.pos[1] - 1
  local lo = math.max(0, row - half)
  local hi = math.min(ctx.line_count, row + half + 1)

  local lines = vim.api.nvim_buf_get_lines(ctx.buf, lo, hi, true)
  local r = row - lo
  return vim.list_slice(lines, 1, r), vim.list_slice(lines, r + 2)
end

return M
