local float = require "coq.lib.float"

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

  float.close(opts.ns)

  local b_w, b_h = border_wh(border)
  local t_w, t_h = vim.o.columns, vim.o.lines
  local width = math.floor((t_w - margin) * relsize) - b_w
  local height = math.floor((t_h - margin) * relsize) - b_h

  local win, buf = float.open {
    ns = opts.ns,
    lines = opts.lines,
    filetype = opts.filetype,
    row = math.floor((t_h - height) / 2),
    col = math.floor((t_w - width) / 2),
    width = width,
    height = height,
    border = border,
    enter = true,
    winhighlight = "Normal:Floating",
  }

  vim.keymap.set({ "n" }, "q", [[<cmd>wincmd c<cr>]], { buffer = buf, noremap = true })

  return win, buf
end

return M
