(function(...)
  local kind = function(node)
    if node:named() then
      return node:type()
    else
      return ""
    end
  end

  local nr = vim.treesitter.get_node_range
  local node_range = function(node, default)
    if nr then
      local lo, _, hi, _ = node_range and node_range(node) or {}
      return lo, hi
    else
      return unpack(default)
    end
  end

  local payload = function(buf, node, type, range)
    if not node:missing() and not node:has_error() then
      local parent = node:parent()
      local grandparent = parent and parent:parent() or nil
      local lo, hi = node_range(node)
      return {
        text = vim.treesitter.get_node_text(node, buf),
        range = {lo, hi},
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

  local iter_nodes = function(buf, lo, hi)
    return coroutine.wrap(
      function()
        local go, parser = pcall(vim.treesitter.get_parser)
        if go then
          local query = vim.treesitter.get_query(parser:lang(), "highlights")
          if query then
            for _, tree in pairs(parser:parse()) do
              for capture, node in query:iter_captures(tree:root(), buf, lo, hi) do
                local pl = payload(buf, node, query.captures[capture], {lo, hi})
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

  COQ.ts_req = function(session)
    vim.schedule(
      function()
        local t1 = vim.loop.now()
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)
        local height = vim.api.nvim_win_get_height(win)
        local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        local filename = vim.api.nvim_buf_get_name(buf)

        local lines = vim.api.nvim_buf_line_count(buf)
        local row, col = unpack(vim.api.nvim_win_get_cursor(win))
        row = row - 1
        local lo, hi =
          math.max(0, row - height),
          math.min(lines, row + height + 1)

        local acc = {}
        for payload in iter_nodes(buf, lo, hi) do
          table.insert(acc, payload)
        end
        local t2 = vim.loop.now()
        COQ.Ts_notify(
          session,
          buf,
          lo,
          hi,
          filetype,
          filename,
          acc,
          (t2 - t1) / 1000
        )
      end
    )
  end
end)(...)
