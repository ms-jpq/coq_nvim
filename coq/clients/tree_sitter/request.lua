(function(...)
  COQts_req = function(request_id)
    COQnotify(request_id, vim.NIL)
  end

  local g1, ts_locals = pcall(require, "nvim-treesitter.locals")
  local g2, parsers = pcall(require, "nvim-treesitter.parsers")
  local g3, ts_utils = pcall(require, "nvim-treesitter.ts_utils")

  if not g1 or not g2 or not g3 then
    return
  else
    local co = coroutine

    local matches = nil
    matches = function(match, kind)
      return co.wrap(
        function()
          if match.node then
            local user_d = {node = match.node, kind = ""}
            co.yield(user_d)
          else
            for kind, submatch in pairs(match) do
              for user_d in matches(submatch, kind) do
                co.yield(user_d)
              end
            end
          end
        end
      )
    end

    local parse = function()
      return co.wrap(
        function()
          for _, d in ipairs(ts_locals.get_definitions(0)) do
            for m in matches(d, "") do
              local text = unpack(ts_utils.get_node_text(m.node, 0))
              if text then
                co.yield({kind = m.kind, text = text})
              end
            end
          end
        end
      )
    end

    COQts_req = function(request_id, pos)
      vim.schedule(
        function()
          local row, col = unpack(pos)
          local acc = {}
          if parsers.has_parser() then
            for payload in parse() do
              table.insert(acc, payload)
            end
          end
          COQnotify(request_id, acc)
        end
      )
    end
  end
end)(...)

