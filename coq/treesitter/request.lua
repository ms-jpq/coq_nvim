(function(...)
  local kind = function(node)
    if node:named() then
      return node:type()
    else
      return ""
    end
  end

  local payload = function(buf, node, type)
    if not node:missing() and not node:has_error() then
      local parent = node:parent()
      local grandparent = parent and parent:parent() or nil
      return {
        text = vim.treesitter.get_node_text(node, buf),
        kind = type,
        parent = parent and
          {
            text = vim.treesitter.get_node_text(parent, buf),
            kind = kind(parent)
          } or
          nil,
        grandparent = grandparent and
          {
            text = vim.treesitter.get_node_text(grandparent, buf),
            kind = kind(grandparent)
          } or
          nil
      }
    end
  end

  local iter_nodes = function(buf, ctx)
    return coroutine.wrap(
      function()
        local lines = vim.api.nvim_buf_line_count(buf)
        local row, col = unpack(vim.api.nvim_win_get_cursor(buf))
        row = row - 1
        local lo, hi = math.max(0, row - ctx), math.min(lines, row + ctx + 1)

        local go, parser = pcall(vim.treesitter.get_parser)
        if go then
          local query = vim.treesitter.get_query(parser:lang(), "highlights")
          if query then
            for _, tree in pairs(parser:parse()) do
              for capture, node in query:iter_captures(tree:root(), buf, lo, hi) do
                local pl = payload(buf, node, query.captures[capture])
                if pl and pl.kind ~= "comment" then
                  coroutine.yield(pl)
                end
              end
            end
          end
        end
      end
    )
  end

  COQ.ts_req = function(session, ctx)
    vim.schedule(
      function()
        local t1 = vim.loop.now()
        local buf = vim.api.nvim_create_buf()
        local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        local acc = {}
        for payload in iter_nodes(buf, ctx) do
          table.insert(acc, payload)
        end
        local t2 = vim.loop.now()
        COQ.Ts_notify(session, buf, filetype, acc, (t2 - t1) / 1000)
      end
    )
  end
end)(...)
