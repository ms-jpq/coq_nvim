local async = require "coq.lib.async"
local fs_cache = require "coq.lib.fs_cache"
local index_m = require "coq.producers.snippets.index"
local loader_m = require "coq.producers.snippets.loader"
local producer = require "coq.lib.producers"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

local index_of = util.once(index_m.new)

---@type fun(settings: config.Settings): snippets.Loader
local loader_of = util.once(loader_m.new)

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  local store = fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "snippets"),
    compute = function(filetype)
      return loader_of(settings).parse(filetype)
    end,
  }

  local by_ft = worker.main(function(s)
    return require("coq.producers.snippets").loader_of_main(s).sources_by_filetype()
  end, settings)

  for ft, sources in pairs(by_ft) do
    async.sleep(0)
    local max_mtime = 0
    for _, src in pairs(sources) do
      if src.mtime > max_mtime then
        max_mtime = src.mtime
      end
    end
    for _, snip in pairs(store.fetch(ft, max_mtime)) do
      index_of(settings).insert(snip)
    end
  end
end

---Main-thread entry-point: each Lua state has its own require cache, so
---calling this from `worker.main` lets the main side memoize independently.
M.loader_of_main = loader_of

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
M.matcher = util.batched(function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }

  for hit in util.shape(settings, ctx, raw) do
    local label = (hit.item.label and hit.item.label ~= "") and hit.item.label or hit.item.word
    local lines = vim.iter(doc_lines(hit.item)):totable()

    local item = util.item(settings, settings.clients.snippets, {
      word = hit.item.word,
      abbr = label,
      kind = "Snippet",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      snippet = hit.item.body,
      doc = #lines > 0 and { lines = lines, filetype = ctx.filetype } or nil,
    })
    coroutine.yield(item)
  end
end)

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
