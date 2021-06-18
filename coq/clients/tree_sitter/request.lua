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
    COQts_req = function(request_id)
    end
  end
end)(...)

