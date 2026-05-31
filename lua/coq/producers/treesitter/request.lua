local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@class treesitter.Payload
---@field text string
---@field kind string
---@field range integer[]
---@field parent? treesitter.Node
---@field grandparent? treesitter.Node

---@param buf integer
M.query = function(buf)
  local h = runtime.current()

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

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
    if h.cancelled then
      return
    end

    for capture_id, node in query:iter_captures(tree:root(), buf, lo, hi) do
      if h.cancelled then
        return
      end

      local kind = query.captures[capture_id]
      if kind ~= "comment" and not node:missing() and not node:has_error() then
        local r_lo, _, r_hi, _ = node:range()
        local parent = node:parent()
        local grandparent = parent and parent:parent() or nil

        coroutine.yield {
          text = vim.treesitter.get_node_text(node, buf),
          kind = kind,
          range = { r_lo, r_hi },
          parent = parent and node_info(parent) or nil,
          grandparent = grandparent and node_info(grandparent) or nil,
        }
        atools.scheduled()
      end
    end
  end
end

return M
