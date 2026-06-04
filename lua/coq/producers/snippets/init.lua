local async = require "coq.lib.async"
local fs_cache = require "coq.lib.fs_cache"
local index_m = require "coq.producers.snippets.index"
local loader_m = require "coq.producers.snippets.loader"
local producer = require "coq.lib.producers"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"

local index_of = util.once(index_m.new)

---@type fun(idle_ctx: idle.Ctx, loader: snippets.Loader): fs_cache.Store<snippets.Item[]>
local cache_of = util.once(function(idle_ctx, loader)
  return fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "snippets"),
    compute = loader.parse,
  }
end)

local seen_filetypes = {}

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  local loader = loader_m.new(settings, idle_ctx.rtps)
  local store = cache_of(idle_ctx, loader)

  local current = {}
  local by_ft = {}
  for ft, srcs in pairs(loader.sources()) do
    current[ft] = true
    local max_mtime = vim.iter(srcs):fold(0, function(acc, s)
      return math.max(acc, s.mtime)
    end)
    by_ft[ft] = store.fetch(ft, max_mtime)
  end

  for ft in pairs(seen_filetypes) do
    if not current[ft] then
      async.sleep(0)
      index_of(settings).prune { filetype = ft }
      store.prune(ft)
    end
  end

  for ft, snips in pairs(by_ft) do
    async.sleep(0)
    index_of(settings).prune { filetype = ft }
    if snips then
      for _, snip in pairs(snips) do
        index_of(settings).insert(snip)
      end
    end
  end

  seen_filetypes = current
end

---@param item snippets.Item
---@return lib.Iterator<string>
local doc_lines = function(item)
  local source = (item.doc and item.doc ~= "") and item.doc or item.body
  return txt.splitlines(source)
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
