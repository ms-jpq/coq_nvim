local M = {}

---@param border string?
---@return integer
---@return integer
local border_wh = function(border)
  if not border or border == "none" then
    return 0, 0
  end
  if border == "shadow" then
    return 1, 1
  end
  return 2, 2
end

---@class commands.FloatOpts
---@field ns string
---@field lines string[]
---@field filetype string
---@field margin? integer
---@field relsize? number
---@field border? string

---@param opts commands.FloatOpts
---@return integer win
---@return integer buf
M.show = function(opts)
  local margin = opts.margin or 0
  local relsize = opts.relsize or 0.95
  local border = opts.border or "rounded"

  for _, win in pairs(vim.api.nvim_list_wins()) do
    if vim.w[win][opts.ns] then
      vim.api.nvim_win_close(win, true)
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = opts.filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  vim.bo[buf].modifiable = false

  local b_w, b_h = border_wh(border)
  local t_w, t_h = vim.o.columns, vim.o.lines
  local width = math.floor((t_w - margin) * relsize) - b_w
  local height = math.floor((t_h - margin) * relsize) - b_h

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    anchor = "NW",
    style = "minimal",
    width = width,
    height = height,
    row = math.floor((t_h - height) / 2),
    col = math.floor((t_w - width) / 2),
    border = border,
    focusable = true,
    noautocmd = true,
  })
  vim.api.nvim_set_option_value("winhighlight", "Normal:Floating", { win = win })
  vim.w[win][opts.ns] = true
  vim.b[buf][opts.ns] = true

  vim.keymap.set({ "n" }, "q", [[<cmd>wincmd c<cr>]], { buffer = buf, noremap = true })

  return win, buf
end

return M
