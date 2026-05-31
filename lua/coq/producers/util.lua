local lib = require "coq.lib"

local M = {}

---@generic T
---@param iter fun(): T?
---@param key fun(item: T): any
---@return fun(): T?
M.dedup = function(iter, key)
  local seen = {}
  return function()
    for item in iter do
      local k = key(item)
      if not seen[k] then
        seen[k] = true
        return item
      end
    end
    return nil
  end
end

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
---@param push producers.Push
M.buffer_bind = function(_, push)
  vim.api.nvim_create_autocmd(vim.tbl_keys(BUFFER_KINDS), {
    group = lib.group,
    callback = function(args)
      push { kind = BUFFER_KINDS[args.event], args = args }
    end,
  })

  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      push { kind = "update", args = { buf = buf } }
    end
  end
end

---@param ev { args: { buf: integer } }
---@return integer
M.buffer_key = function(ev)
  return ev.args.buf
end

return M
