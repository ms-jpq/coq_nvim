local handle = require "coq.lib.async.handle"
local search = require "coq.lib.index"

---@class tmux.Item
---@field word string
---@field pane string

---@return index.Searcher<tmux.Item>
local leaf = function()
  local items = {}
  return {
    close = function()
      items = {}
    end,
    insert = function(item)
      table.insert(items, item)
    end,
    prune = function(ctx)
      if ctx.pane ~= nil then
        items = vim
          .iter(items)
          :filter(function(it)
            return it.pane ~= ctx.pane
          end)
          :totable()
      else
        items = {}
      end
    end,
    search = function(ctx)
      local snapshot = items
      local cword = ctx.cword
      local h = handle.new()
      return search.iter(h, function()
        for _, item in ipairs(snapshot) do
          if item.word ~= cword then
            coroutine.yield(item)
          end
        end
      end)
    end,
  }
end

local M = {}

local instance = search.indexed {
  key_item = function(i)
    return string.sub(i.word, 1, 2)
  end,
  key_ctx = function(c)
    if c.line_before == nil then
      return nil
    end
    local last = string.match(c.line_before, "[%w_]+$")
    return last and #last >= 2 and string.sub(last, 1, 2) or nil
  end,
  child = leaf,
}

M.search = instance.search
M.insert = instance.insert
M.prune = instance.prune
M.close = instance.close

return M
