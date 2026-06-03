local index_m = require "coq.producers.snippets.index"
local producer = require "coq.lib.producers"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"

local index_of = util.once(index_m.new)

local M = {}

---@param _ config.Settings
---@param _idle_ctx idle.Ctx
M.idle = function(_, _idle_ctx)
  -- TODO: load snippet bundles from disk and populate `index(settings)`.
  -- v1 used a per-source mtime-tracked SQLite cache. Stub for now.
  --
  -- index(settings).insert {
  --   word = ...,
  --   body = ...,
  --   filetype = ...,
  --   label = ...,
  --   doc = ...,
  -- }
end

---@param item snippets.Item
---@return lib.Iterator<string>
local doc_lines = function(item)
  return coroutine.wrap(function()
    local source = (item.doc and item.doc ~= "") and item.doc or item.body
    for line in txt.splitlines(source) do
      coroutine.yield(line)
    end
  end)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.snippets

  local raw = index_of(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }
  local shaped = util.shape(settings, ctx, raw)

  for hit in shaped do
    local label = (hit.item.label and hit.item.label ~= "") and hit.item.label or hit.item.word
    local lines = vim.iter(doc_lines(hit.item)):totable()
    coroutine.yield(util.item(settings, opts, {
      word = hit.item.word,
      abbr = label,
      kind = "Snippet",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      snippet = hit.item.body,
      doc = #lines > 0 and { lines = lines, filetype = ctx.filetype } or nil,
    }))
  end
end

---@return producers.Producer<ctx.full>
M.new = function()
  return producer.threaded {
    idle = function(...)
      require("coq.producers.snippets").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.snippets").matcher(...)
    end,
  }
end

return M
