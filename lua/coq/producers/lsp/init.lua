local lib = require "coq.lib"
local request = require "coq.producers.lsp.request"
local threaded = require "coq.lib.producers.threaded"
local worker = require "coq.lib.worker"

local M = {}

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.lsp
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]

  local row = ctx.pos[1] - 1
  local col = ctx.pos[2]

  for entry in
    worker.main_stream(request.query, ctx.buf, row, col) --[[@as lib.Iterator<lsp.RequestItem>]]
  do
    local item = entry.item
    local label = item.label or ""
    local insert_text = item.insertText or label
    local is_snippet = item.insertTextFormat == 2
    local filter = item.filterText or label

    coroutine.yield {
      word = is_snippet and label or insert_text,
      abbr = label,
      kind = entry.kind,
      menu = menu,
      meta = {
        filter = filter,
        snippet = is_snippet and insert_text or nil,
        source = opts.short_name,
        always_on_top = false,
        lsp = {
          client_id = entry.client_id,
          item = item,
          additional_text_edits = item.additionalTextEdits,
          position_encoding = entry.offset_encoding,
          command = item.command,
        },
      },
    }
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return threaded.new {
    settings = settings,
    max_pulls = settings.clients.lsp.max_pulls,
    bind = lib.noop,
    idle = lib.noop,
    matcher = function(...)
      require("coq.producers.lsp").matcher(...)
    end,
  }
end

return M
