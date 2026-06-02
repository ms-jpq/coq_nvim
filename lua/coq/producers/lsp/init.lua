local async = require "coq.lib.async"
local lib = require "coq.lib"
local request = require "coq.producers.lsp.request"
local set = require "coq.lib.set"

local M = {}

---@param settings config.Settings
local matcher = function(settings, ctx)
  return async.wrap(function()
    local opts = settings.clients.lsp
    local sc = settings.display.pum.source_context
    local menu = sc[1] .. opts.short_name .. sc[2]

    local ignored = set.new(opts.ignored_servers)
    local pinned = set.new(opts.always_on_top)

    for entry in request.query(ignored, ctx) do
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
          always_on_top = pinned[entry.client_name] == true,
          lsp = {
            client_id = entry.client_id,
            item = item,
            position_encoding = entry.offset_encoding,
          },
        },
      }
    end
  end)
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return {
    bind = lib.noop,
    idle = lib.noop,
    search = function(ctx)
      return matcher(settings, ctx)
    end,
  }
end

return M
