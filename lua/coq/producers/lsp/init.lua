local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"
local match = require "coq.lib.index.rank.match"
local request = require "coq.producers.lsp.request"
local set = require "coq.lib.set"
local util = require "coq.producers.util"

local SOURCE = "lsp"

local M = {}

---@return producers.Producer<ctx.full>
M.new = function()
  return {
    source = SOURCE,
    idle = lib.noop,
    search = function(settings, ctx)
      return closable.iter(function(defer)
        atools.scheduled()
        local lhs, rhs = unpack(settings.display.pum.source_context)
        local menu = lhs .. settings.clients.lsp.short_name .. rhs

        local ignored = set.new(settings.clients.lsp.ignored_servers)
        local pinned = set.new(settings.clients.lsp.always_on_top)

        local close, query = request.query(ignored, ctx)
        defer(close)

        for batch in query do
          local acc = vim
            .iter(batch)
            :map(function(entry)
              local item = entry.item
              local label = item.label or ""
              local insert_text = item.insertText or label
              local is_snippet = item.insertTextFormat == 2
              local filter = item.filterText or label

              return {
                word = is_snippet and label or insert_text,
                abbr = label,
                kind = entry.kind,
                menu = menu,
                meta = {
                  uid = util.uid(),
                  filter = filter,
                  fuzzy = match.score(ctx.keyword_before, filter),
                  source = SOURCE,
                  always_on_top = pinned[entry.client_name] == true,
                  lsp = {
                    client_id = entry.client_id,
                    client_name = entry.client_name,
                    item = item,
                    position_encoding = entry.offset_encoding,
                  },
                },
              }
            end)
            :totable()

          coroutine.yield(acc)
        end
      end)
    end,
  }
end

return M
