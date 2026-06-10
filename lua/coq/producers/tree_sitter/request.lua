local atools = require "coq.lib.atools"
local buffers = require "coq.lib.buffers"

local M = {}

---@class treesitter.Payload
---@field text string
---@field kind string
---@field range [integer, integer]
---@field parent? treesitter.Node
---@field grandparent? treesitter.Node

---@param buf integer
M.query = function(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lo, hi = buffers.window_around_cursor(buf)

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

  local trees = parser:parse() or {}
  local tick = vim.b[buf].changedtick

  for _, tree in pairs(trees) do
    for capture_id, node in query:iter_captures(tree:root(), buf, lo, hi) do
      local kind = query.captures[capture_id]
      if kind ~= "comment" and not node:missing() and not node:has_error() then
        local text = vim.treesitter.get_node_text(node, buf)

        if type(text) == "string" and text ~= "" then
          local r_lo, _, r_hi, _ = node:range()
          local parent = node:parent()
          local grandparent = parent and parent:parent() or nil
          local payload = {
            text = text,
            kind = kind,
            range = { r_lo, r_hi },
            parent = parent and node_info(parent) or nil,
            grandparent = grandparent and node_info(grandparent) or nil,
          }

          if not coroutine.yield(payload) then
            return
          end

          atools.scheduled()
          if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].changedtick ~= tick then
            return
          end
        end
      end
    end
  end
end

return M
