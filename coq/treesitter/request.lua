(function(...)
  local kind = function(node)
    if node:named() then
      return node:type()
    else
      return ""
    end
  end

  local payload = function(node, type)
    if not node:missing() and not node:has_error() then
      local text = vim.treesitter.get_node_text(node, 0)
      local parent = node:parent()
      local grandparent = parent and parent:parent() or nil
      if text then
        return {
          text = text,
          kind = type,
          parent = parent and
            {
              text = vim.treesitter.get_node_text(parent, 0),
              kind = kind(parent)
            } or
            nil,
          grandparent = grandparent and
            {
              text = vim.treesitter.get_node_text(grandparent, 0),
              kind = kind(grandparent)
            } or
            nil
        }
      end
    end
  end

  local iter_nodes = function()
    return coroutine.wrap(
      function()
        local go, parser = pcall(vim.treesitter.get_parser)
        if go then
          local query = vim.treesitter.get_query(parser:lang(), "highlights")
          local trees = parser:parse()

          for _, tree in pairs(trees) do
            for capture, node in query:iter_captures(tree:root(), 0) do
              local pl = payload(node, query.captures[capture])
              if pl then
                coroutine.yield(pl)
              end
            end
          end
        end
      end
    )
  end

  COQts_req = function(session, pos)
    vim.schedule(
      function()
        local acc = {}
        for payload in iter_nodes() do
          table.insert(acc, payload)
        end
        COQts_notify(session, acc)
      end
    )
  end
end)(...)
