local M = {}

M.NS = "coq.float"

---@param ns string?
---@return integer[]
M.list = function(ns)
  return vim
    .iter(vim.api.nvim_list_wins())
    :filter(function(win)
      local tag = vim.w[win][M.NS]
      return tag ~= nil and (ns == nil or tag == ns)
    end)
    :totable()
end

---@param ns string?
M.close = function(ns)
  for _, win in pairs(M.list(ns)) do
    vim.api.nvim_win_close(win, true)
  end
end

---@class lib.float.Opts
---@field ns string
---@field lines string[]
---@field filetype? string
---@field row integer
---@field col integer
---@field width integer
---@field height integer
---@field border? string
---@field enter? boolean
---@field focusable? boolean
---@field winhighlight? string
---@field conceal? boolean

---@param opts lib.float.Opts
---@return integer win
---@return integer buf
M.open = function(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  if opts.filetype and opts.filetype ~= "" then
    vim.bo[buf].filetype = opts.filetype
  end
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, opts.enter == true, {
    relative = "editor",
    anchor = "NW",
    style = "minimal",
    row = opts.row,
    col = opts.col,
    width = opts.width,
    height = opts.height,
    border = opts.border,
    focusable = opts.focusable ~= false,
  })

  if opts.winhighlight then
    vim.api.nvim_set_option_value("winhighlight", opts.winhighlight, { win = win })
  end
  if opts.conceal then
    vim.wo[win].conceallevel = 2
    vim.wo[win].concealcursor = "n"
  end

  vim.w[win][M.NS] = opts.ns

  return win, buf
end

return M
