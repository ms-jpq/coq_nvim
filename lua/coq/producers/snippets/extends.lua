local set = require "coq.lib.set"

---@alias snippets.Extends table<string, lib.Set<string>>

---@param es snippets.Extends[]
---@return snippets.Extends
local merge = function(es)
  ---@type snippets.Extends
  local acc = {}

  for _, e in pairs(es) do
    for ft, parents in pairs(e) do
      acc[ft] = acc[ft] or {}
      for parent in pairs(parents) do
        acc[ft][parent] = true
      end
    end
  end

  return acc
end

local M = {}

---@param depth integer
---@param es snippets.Extends[]
---@return snippets.Extends
M.denormalize = function(depth, es)
  local graph = merge(es)
  ---@type snippets.Extends

  local acc = {}
  for ft in pairs(graph) do
    local seen = set.new { ft }
    local frontier = { ft }

    for _ = 1, depth do
      local next_frontier = {}
      for _, cur in pairs(frontier) do
        for parent in pairs(graph[cur] or {}) do
          if not seen[parent] then
            seen[parent] = true
            table.insert(next_frontier, parent)
          end
        end
      end
      if #next_frontier == 0 then
        break
      end
      frontier = next_frontier
    end
    acc[ft] = seen
  end

  return acc
end

return M
