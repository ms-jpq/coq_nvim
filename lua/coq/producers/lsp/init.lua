local closable = require "coq.lib.closable"
local lib = require "coq.lib"
local match = require "coq.lib.index.rank.match"
local request = require "coq.producers.lsp.request"
local set = require "coq.lib.set"
local util = require "coq.producers.util"

local M = {}

---@return producers.Producer<ctx.full>
M.new = function()
  return {
    bind = lib.noop,
    idle = lib.noop,
    search = function(settings, ctx)
      return closable.iter(function(defer)
        local opts = settings.clients.lsp
        local lhs, rhs = unpack(settings.display.pum.source_context)
        local menu = lhs .. opts.short_name .. rhs

        local ignored = set.new(opts.ignored_servers)
        local pinned = set.new(opts.always_on_top)

        local close, query = request.query(ignored, ctx)
        defer(close)

        util.batched(function(yield)
          for entry in query do
            local item = entry.item
            local label = item.label or ""
            local insert_text = item.insertText or label
            local is_snippet = item.insertTextFormat == 2
            local filter = item.filterText or label

            yield {
              word = is_snippet and label or insert_text,
              abbr = label,
              kind = entry.kind,
              menu = menu,
              meta = {
                uid = util.uid(),
                filter = filter,
                fuzzy = match.score(ctx.keyword_before, filter),
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
      end)
    end,
  }
end

return M
