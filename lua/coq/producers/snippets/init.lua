local async = require "coq.lib.async"
local extends_m = require "coq.producers.snippets.extends"
local fs_cache = require "coq.lib.fs_cache"
local index_m = require "coq.producers.snippets.index"
local itertools = require "coq.lib.itertools"
local lib = require "coq.lib"
local loader_m = require "coq.producers.snippets.loader"
local set = require "coq.lib.set"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"

local EXTENDS_DEPTH = 9

local SOURCE = "snippets"

local index_of = util.once(index_m.new)

---@type fun(idle_ctx: idle.Ctx, loader: snippets.Loader): fs_cache.Store<snippets.Item[]>
local cache_of = util.once(function(idle_ctx, loader)
  return fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "snippets"),
    compute = function(filetype)
      return lib.scope(function(defer)
        local close, iter = loader.parse(filetype)
        defer(close)
        return vim.iter(iter):totable()
      end)
    end,
  }
end)

---@param srcs snippets.Source[]
---@return string
local fingerprint = function(srcs)
  local parts = vim
    .iter(srcs)
    :map(function(s)
      return s.path .. ":" .. s.mtime
    end)
    :totable()
  table.sort(parts)
  return table.concat(parts, "|")
end

local seen_filetypes = {}
local seen_fp_by_ft = {}

---@type snippets.Extends
local closure_of = {}

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  local loader = loader_m.new(settings, idle_ctx)
  local store = cache_of(idle_ctx, loader)

  local current = set.new {}
  local current_fp = {}
  local by_ft = {}
  for ft, srcs in pairs(loader.sources()) do
    current[ft] = true
    local fp = fingerprint(srcs)
    current_fp[ft] = fp

    if seen_fp_by_ft[ft] and seen_fp_by_ft[ft] ~= fp then
      store.prune(ft)
    end

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
  seen_fp_by_ft = current_fp
  closure_of = extends_m.denormalize(EXTENDS_DEPTH, loader.extends())
end

---@param item snippets.Item
---@return lib.Iterator<string>
local doc_lines = function(item)
  local source = item.doc ~= "" and item.doc or item.body
  return txt.splitlines(source)
end

---@param settings config.Settings
M.matcher = util.batched(function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local idx = index_of(settings)
  local fts = closure_of[ctx.filetype] or { [ctx.filetype] = true }
  local raws = {
    idx.search { filetype = "*", keyword_before = ctx.keyword_before },
    idx.search { filetype = "_", keyword_before = ctx.keyword_before },
  }
  for ft in pairs(fts) do
    table.insert(raws, idx.search { filetype = ft, keyword_before = ctx.keyword_before })
  end
  local raw = itertools.chain(unpack(raws)) --[[@as fun(): index.Hit<snippets.Item>?]]

  for hit in util.shape(settings, ctx, raw) do
    local label = (hit.item.label and hit.item.label ~= "") and hit.item.label or hit.item.word
    local item = util.item(settings, SOURCE, {
      word = hit.item.word,
      abbr = label,
      kind = "Snippet",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      snippet = hit.item.body,
      doc = util.doc(ctx.filetype, doc_lines(hit.item)),
    })
    if not coroutine.yield(item) then
      return
    end
  end
end)

M.new = util.threaded_module(SOURCE)

return M
