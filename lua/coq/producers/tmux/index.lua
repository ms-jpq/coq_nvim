local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class tmux.PaneMeta
---@field session_name string
---@field window_index string
---@field window_name string
---@field pane_index string
---@field pane_title string

---@class tmux.Item
---@field word string
---@field pane string
---@field meta tmux.PaneMeta

---@class tmux.Ctx
---@field pane? string
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<tmux.Ctx, tmux.Item>
M.new = function(settings)
  return search.indexed {
    insert_key = function(item)
      return item.pane
    end,
    query_key = function(ctx)
      return ctx.pane
    end,
    child = util.word_search(settings),
  }
end

return M
