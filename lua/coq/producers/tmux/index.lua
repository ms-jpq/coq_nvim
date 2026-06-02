local fuzzy = require "coq.lib.index.fuzzy"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

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
  local prefix = settings.match.exact_matches

  ---@return index.Searcher<tmux.Ctx, tmux.Item>
  local word_trie = function()
    return trie.new {
      insert_key = function(item)
        return item.word
      end,
      query_key = function(ctx)
        if ctx.keyword_before == nil or ctx.keyword_before == "" then
          return nil
        end
        return ctx.keyword_before
      end,
      prefix = prefix,
      child = function()
        return fuzzy.new {
          insert_key = function(item)
            return item.word
          end,
        }
      end,
    }
  end

  return search.indexed {
    insert_key = function(item)
      return item.pane
    end,
    query_key = function(ctx)
      return ctx.pane
    end,
    child = word_trie,
  }
end

return M
