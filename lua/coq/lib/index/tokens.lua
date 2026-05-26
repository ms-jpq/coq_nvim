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
  return vim.iter(matches):map(function(m)
    return m.text
  end)
end

M.locality = function(buf, lines)
  return M.words(buf, lines):fold({}, function(acc, word)
    acc[word] = (acc[word] or 0) + 1
    return acc
  end)
end

return M
