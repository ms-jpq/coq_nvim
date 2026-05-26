local M = {}

M.surround = function(ctx)
  local half = math.floor(vim.api.nvim_win_get_height(ctx.win) / 2)
  local row = ctx.pos[1] - 1
  local lo = math.max(0, row - half)
  local hi = math.min(ctx.line_count, row + half + 1)

  return vim.api.nvim_buf_get_lines(ctx.buf, lo, hi, true)
end

M.words = function(buf, lines)
  local matches = vim.api.nvim_buf_call(buf, function()
    return vim.fn.matchstrlist(lines, [[\k\+]])
  end)

  local i = 0
  return function()
    i = i + 1
    local m = matches[i]
    return m and m.text
  end
end

M.locality = function(buf, lines)
  local locality = {}
  for word in M.words(buf, lines) do
    locality[word] = (locality[word] or 0) + 1
  end
  return locality
end

return M
