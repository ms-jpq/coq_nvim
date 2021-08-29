(function(...)
  local iter_nodes = function()
    return coroutine.wrap(
      function()
        local go, parser = pcall(vim.treesitter.get_parser)
        if go then
          local trees = parser:parse()

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

          for _, tree in ipairs(trees) do
            for node in iter(tree:root()) do
              coroutine.yield(node)
            end
          end
        end
      end
    )
  end

  local text_for = function(node)
    local r1, c1, r2, c2 = node:range()
    local lines = vim.api.nvim_buf_get_lines(0, r1, r2 + 1, false)
    local len = #lines
    if len == 1 then
      local word = unpack(lines)
      return string.sub(word, c1 + 1, c2)
    else
      local head, tail = unpack({lines[1], lines[len]})
      local pre = string.sub(head, c1 + 1, #head)
      local post = string.sub(tail, 1, c2)
      lines[1], lines[len] = unpack({pre, post})
      local word = table.concat(lines, "")
      return word
    end
  end

  COQts_req = function(session, pos)
    local acc = {}
    vim.schedule(
      function()
        for node in iter_nodes() do
          table.insert(acc, {text = text_for(node), kind = node:type()})
        end
        COQts_notify(session, acc)
      end
    )
  end
end)(...)
