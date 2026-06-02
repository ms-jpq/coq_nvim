local lib = require "coq.lib"

local M = {}

local BUFFER_KINDS = {
  BufEnter = "update",
  BufRead = "update",
  BufWinEnter = "update",
  TextChanged = "update",
  TextChangedI = "update",
  BufDelete = "remove",
  BufWipeout = "remove",
}

---@param _ async.Nursery
---@param push fun(buf: integer, kind: 'update' | 'remove')
M.buffer_bind = function(_, push)
  vim.api.nvim_create_autocmd(vim.tbl_keys(BUFFER_KINDS), {
    group = lib.group,
    callback = function(args)
      push(args.buf, BUFFER_KINDS[args.event])
    end,
  })

  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      push(buf, "update")
    end
  end
end

return M
