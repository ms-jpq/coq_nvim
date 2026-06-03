local M = {}

local NS = "__coq_float__"

---@class commands.FloatOpts
---@field lines string[]
---@field filetype string
---@field border? string
---@field ratio? number

---@param opts commands.FloatOpts
---@return integer win
---@return integer buf
M.show = function(opts)
  local ratio = opts.ratio or 0.95

  for _, win in pairs(vim.api.nvim_list_wins()) do
    if vim.w[win][NS] then
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

  local ui = { width = vim.o.columns, height = vim.o.lines }
  local w, h = math.floor(ui.width * ratio), math.floor(ui.height * ratio)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = w,
    height = h,
    row = math.floor((ui.height - h) / 2),
    col = math.floor((ui.width - w) / 2),
    border = opts.border or "rounded",
    style = "minimal",
  })
  vim.w[win][NS] = true

  vim.keymap.set({ "n" }, "q", [[<cmd>wincmd c<cr>]], { buffer = buf, noremap = true })

  return win, buf
end

return M
