local context = require "coq.lib.context"
local util = require "coq.producers.util"

local M = {}

---@class treesitter.Payload
---@field text string
---@field kind string
---@field range [integer, integer]
---@field parent? treesitter.Node
---@field grandparent? treesitter.Node

---@param buf integer
M.query = function(buf)
  if not util.is_live(buf) then
    return
  end

  local tick = vim.b[buf].changedtick

  local lo, hi = context.window_around_cursor(buf)

  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return
  end

  local query = vim.treesitter.query.get(parser:lang(), "highlights")
  if not query then
    return
  end

  local node_info = function(node)
    return {
      text = vim.treesitter.get_node_text(node, buf),
      kind = node:named() and node:type() or "",
    }
  end

  for _, tree in pairs(parser:parse() or {}) do
    for capture_id, node in query:iter_captures(tree:root(), buf, lo, hi) do
      local kind = query.captures[capture_id]
      if kind ~= "comment" and not node:missing() and not node:has_error() then
        local r_lo, _, r_hi, _ = node:range()
        local parent = node:parent()
        local grandparent = parent and parent:parent() or nil

        if
          not coroutine.yield {
            text = vim.treesitter.get_node_text(node, buf),
            kind = kind,
            range = { r_lo, r_hi },
            parent = parent and node_info(parent) or nil,
            grandparent = grandparent and node_info(grandparent) or nil,
          }
        then
          return
        end

        if not util.is_live(buf) or vim.b[buf].changedtick ~= tick then
          return
        end
      end
    end
  end
end

return M
