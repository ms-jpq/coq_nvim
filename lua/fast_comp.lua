local fn = vim.fn
local lsp = vim.lsp

local cancel = nil


local list_comp_candidates = function (request_id)
  if cancel then
    cancel()
    cancel = nil
  end

  local pos = lsp.util.make_position_params()
  _, cancel = lsp.buf_request(0, "textDocument/completion", pos, function (err, _, rows)
    assert(not err, err)
    fn._FCnotify("lsp", request_id, rows)
  end)
end


return {
  list_comp_candidates = list_comp_candidates
}
