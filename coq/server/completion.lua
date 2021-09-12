(function(...)
  COQsend_comp = function(col, items)
    vim.schedule(
      function()
        local legal_modes = {
          ["i"] = true,
          ["ic"] = true,
          ["ix"] = true
        }
        local legal_cmodes = {
          [""] = true,
          ["eval"] = true,
          ["function"] = true,
          ["ctrl_x"] = true
        }
        local mode = vim.api.nvim_get_mode().mode
        local comp_mode = vim.fn.complete_info({"mode"}).mode
        if legal_modes[mode] and legal_cmodes[comp_mode] then
          -- when `#items ~= 0` there is something to show
          -- when `#items == 0` but `comp_mode == "eval"` there is something to close
          if #items ~= 0 or comp_mode == "eval" then
            vim.fn.complete(col, items)
          end
        end
      end
    )
  end
end)(...)
