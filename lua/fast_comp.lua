local fn = vim.fn
local lsp = vim.lsp

local cancel = nil


local list_comp_candidates = function (request_id)
  if cancel then
    cancel()
    cancel = nil
  end

  if #lsp.buf_get_clients() == 0 then
    fn._FCnotify("lsp", request_id, {})
  else
    local pos = lsp.util.make_position_params()
    _, cancel = lsp.buf_request(0, "textDocument/completion", pos, function (err, _, ans)
      assert(not err, err)
      local rows = lsp.util.extract_completion_items(ans)
      fn._FCnotify("lsp", request_id, rows)
    end)
  end
end


return {
  list_comp_candidates = list_comp_candidates
}
