(function(...)
  local iter = nil
  iter = function(root)
    return coroutine.wrap(
      function()
        if root:child_count() == 0 then
          coroutine.yield(root)
        else
          for node in root:iter_children() do
            for n in iter(node) do
              coroutine.yield(n)
            end
          end
        end
      end
    )
  end

  local iter_nodes = function()
    return coroutine.wrap(
      function()
        local go, parser = pcall(vim.treesitter.get_parser)
        if go then
          local trees = parser:parse()

          for _, tree in ipairs(trees) do
            for node in iter(tree:root()) do
              coroutine.yield(node)
            end
          end
        end
      end
    )
  end

  local kind = function(node)
    if node:named() then
      return node:type()
    else
      return ""
    end
  end

  COQts_req = function(session, pos)
    vim.schedule(
      function()
        local acc = {}
        for node in iter_nodes() do
          if not node:missing() and not node:has_error() then
            local text = vim.treesitter.get_node_text(node, 0)
            local parent = node:parent()
            local grandparent = parent and parent:parent() or nil
            if text then
              table.insert(
                acc,
                {
                  text = text,
                  kind = kind(node),
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
              )
            end
          end
        end
        COQts_notify(session, acc)
      end
    )
  end
end)(...)
