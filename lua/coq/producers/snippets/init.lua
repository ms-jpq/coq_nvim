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

---@param src snippets.Source
---@return snippets.Extends extends
---@return snippets.Sourced sourced
local parse_src = function(src)
  local err, extends, sourced = loaders.parse(src)
  if err then
    errs.report(err)
  end
  return extends, sourced
end

---@type fun(settings: config.Settings, idle_ctx: idle.Ctx): fs_cache.Store<snippets.Item[]>
local cache_of = util.once(function(settings, idle_ctx)
  return fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "snippets"),
    compute = function(filetype)
      return lib.scope(function(defer)
        local close, iter = sources.list(settings, idle_ctx)
        defer(close)
        local items = {}
        for src in iter do
          local _, sourced = parse_src(src)
          if vim.tbl_contains(sourced.filetypes, filetype) then
            for _, item in pairs(sourced.snippets) do
              if item.filetype == filetype then
                table.insert(items, item)
              end
            end
          end
        end
        return items
      end)
    end,
  }
end)

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@return table<string, snippets.Source[]> sources_by_ft
---@return snippets.Extends[] extends_all
local walk = function(settings, idle_ctx)
  local by_ft = {}
  ---@type snippets.Extends[]
  local all = {}
  lib.scope(function(defer)
    local close, iter = sources.list(settings, idle_ctx)
    defer(close)
    for src in iter do
      local extends, sourced = parse_src(src)
      table.insert(all, extends)
      for _, ft in pairs(sourced.filetypes) do
        by_ft[ft] = by_ft[ft] or {}
        table.insert(by_ft[ft], src)
      end
    end
  end)
  return by_ft, all
end

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
  local store = cache_of(settings, idle_ctx)
  local sources_by_ft, extends_all = walk(settings, idle_ctx)

  local current = set.new {}
  local current_fp = {}
  local by_ft = {}
  for ft, srcs in pairs(sources_by_ft) do
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
  closure_of = extends_m.denormalize(EXTENDS_DEPTH, extends_all)
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
  local raw = async.wrap(function()
    local fts = set.new { "*", "_" }
    for ft in pairs(closure_of[ctx.filetype] or set.new { ctx.filetype }) do
      fts[ft] = true
    end
    for ft in pairs(fts) do
      for hit in idx.search { filetype = ft, keyword_before = ctx.keyword_before } do
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
