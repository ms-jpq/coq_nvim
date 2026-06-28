local M = {}

---@generic T
---@param items T[]
---@return lib.Set<T>
M.set_of = function(items)
  local s = {}
  for _, v in ipairs(items) do
    s[v] = true
  end
  return s
end

---@param lines? string[]
---@return integer buf
M.scratch_buf = function(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  end
  return buf
end

---@param overrides? table
---@return ctx.full
M.ctx_of = function(overrides)
  local base = {
    win = 0,
    buf = 0,
    pos = { 1, 0, 0, 0 },
    changedtick = 0,
    line = "",
    filetype = "",
    manual = false,
    cwd = "",
    filename = "",
    linesep = "\n",
    iskeyword = "@,48-57,_,192-255",
    wildignore = "",
    comment = { "", "" },
    line_before = "",
    keyword_before = "",
    keyword_before_has_upper = false,
    symbol_before = "",
    match_before = "",
  }
  return vim.tbl_deep_extend("force", base, overrides or {}) --[[@as ctx.full]]
end

return M
