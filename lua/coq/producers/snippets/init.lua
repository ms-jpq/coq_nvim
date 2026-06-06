local async = require "coq.lib.async"
local errs = require "coq.lib.errs"
local extends_m = require "coq.producers.snippets.extends"
local fs_cache = require "coq.lib.fs_cache"
local index_m = require "coq.producers.snippets.index"
local lib = require "coq.lib"
local loaders = require "coq.producers.snippets.loaders"
local set = require "coq.lib.set"
local sources = require "coq.producers.snippets.sources"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"

local EXTENDS_DEPTH = 9

local SOURCE = "snippets"

local index_of = util.once(index_m.new)

---@class snippets.Cached
---@field extends string[]
---@field items snippets.Item[]

---@type fun(settings: config.Settings, idle_ctx: idle.Ctx): fs_cache.Store<snippets.Cached>
local cache_of = util.once(function(settings, idle_ctx)
  return fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "snippets"),
    compute = function(filetype)
      return lib.scope(function(defer)
        local close, iter = sources.list(settings, idle_ctx, filetype, idle_ctx.ctx.filename)
        defer(close)

        local errors = {}
        local extends = set.new {}
        local items = {}
        for src in iter do
          local err, fts, sourced = loaders.parse(src)
          if err then
            table.insert(errors, err)
          end
          for _, extending in pairs(fts) do
            extends[extending] = true
          end
          for _, item in pairs(sourced.snippets) do
            table.insert(items, item)
          end
        end

        errs.check_raise(errors)
        return { extends = vim.tbl_keys(extends), items = items }
      end)
    end,
  }
end)

---@type snippets.Extends
local closure_of = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@param target string
---@return snippets.Cached
local fetch_ft = function(settings, idle_ctx, target)
  return lib.scope(function(defer)
    local close, iter = sources.list(settings, idle_ctx, target, idle_ctx.ctx.filename)
    defer(close)

    local store = cache_of(settings, idle_ctx)
    local max_mtime = vim.iter(iter):fold(0, function(a, s)
      return math.max(a, s.mtime)
    end)
    local cached = store.fetch(target, max_mtime) or { extends = {}, items = {} }
    return { extends = cached.extends, items = cached.items }
  end)
end

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  local idx = index_of(settings)
  local ft = string.lower(idle_ctx.ctx.filetype)

  ---@type snippets.Extends[]
  local all_extends = {}

  for target, cached in
    extends_m.traverse(ft, function(t)
      return fetch_ft(settings, idle_ctx, t)
    end)
  do
    table.insert(all_extends, { [target] = set.new(cached.extends) })

    async.sleep(0)
    idx.prune { filetype = target }
    for i, item in ipairs(cached.items) do
      idx.insert(item)
      if i % util.BATCH == 0 then
        async.sleep(0)
      end
    end
  end

  for target, parents in pairs(extends_m.denormalize(EXTENDS_DEPTH, all_extends)) do
    closure_of[target] = parents
  end
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

  local filetype = string.lower(ctx.filetype)
  local idx = index_of(settings)

  local raw = async.wrap(function()
    local fts = set.new(extends_m.IMPLICIT)
    for ft in pairs(closure_of[filetype] or set.new { filetype }) do
      fts[ft] = true
    end
    for ft in pairs(fts) do
      for hit in idx.search { filetype = ft, match_before = ctx.match_before } do
        coroutine.yield(hit)
      end
    end
  end) --[[@as fun(): index.Hit<snippets.Item>?]]

  for hit in util.shape(settings, ctx, raw) do
    local item = util.item(settings, SOURCE, {
      word = hit.item.word,
      abbr = hit.item.label ~= "" and hit.item.label or hit.item.word,
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
