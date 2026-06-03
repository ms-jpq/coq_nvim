local async = require "coq.lib.async"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local fs_cache = require "coq.lib.fs_cache"
local index_m = require "coq.producers.ctags.index"
local parse = require "coq.producers.ctags.parse"
local path_fmt = require "coq.producers.path_fmt"
local producer = require "coq.lib.producers"
local run = require "coq.producers.ctags.run"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

local index_of = util.once(index_m.new)

---@type fun(idle_ctx: idle.Ctx): fs_cache.Store<ctags.Tag[]>
local cache_of = util.once(function(idle_ctx)
  return fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "tags"),
    compute = function(filename)
      local out = run.run("ctags", { filename })
      if not out then
        return {}
      end
      return vim.iter(parse.parse(out)):totable()
    end,
  }
end)

local M = {}

---@class ctags.Meta
---@field mtime integer
---@field filename string

---@param buf integer
---@param previous? ctags.Meta
---@return ctags.Meta?
M.buffer_meta = function(buf, previous)
  if not util.is_live(buf) then
    return nil
  end
  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == "" then
    return nil
  end
  local mtime = fs_cache.mtime_ns(filename)
  if not mtime then
    return nil
  end

  if previous and mtime <= previous.mtime then
    return nil
  end
  return { mtime = mtime, filename = filename }
end

---@type fun(settings: config.Settings): fun(idle_ctx: idle.Ctx)
local tracker_of = util.once(function(settings)
  return buf_tracker.new {
    compare = function(buf, previous)
      return worker.main(function(...)
        return require("coq.producers.ctags").buffer_meta(...)
      end, buf, previous)
    end,
    index = function(idle_ctx, metas)
      local store = cache_of(idle_ctx)
      for _, m in pairs(metas) do
        async.sleep(0)
        for _, tag in pairs(store.fetch(m.filename, m.mtime)) do
          index_of(settings).insert(tag --[[@as ctags.Item]])
        end
      end
    end,
    prune = function(idle_ctx, stale)
      local store = cache_of(idle_ctx)
      for _, meta in pairs(stale) do
        store.prune(meta.filename)
        index_of(settings).prune { filename = meta.filename }
      end
    end,
  }
end)

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker_of(settings)(idle_ctx)
end

---@param opts config.CtagsClient
---@param ctx ctx.full
---@param tag ctags.Item
---@return lib.Iterator<string>
local doc_iter = function(opts, ctx, tag)
  return coroutine.wrap(function()
    coroutine.yield(path_fmt.fmt(ctx.cwd, tag.filename, ctx.filename) .. ":" .. tag.line)

    if tag.scopeKind and tag.scope then
      coroutine.yield(tag.scopeKind .. opts.path_sep .. tag.scope .. opts.parent_scope)
    elseif tag.scopeKind then
      coroutine.yield(tag.scopeKind .. opts.parent_scope)
    elseif tag.scope then
      coroutine.yield(tag.scope .. opts.parent_scope)
    end

    local _, _, ref = string.find(tag.typeref or "", "^[^:]+:(.*)$")
    if tag.access and ref then
      coroutine.yield(tag.access .. opts.path_sep .. tag.kind .. opts.path_sep .. ref)
    elseif tag.access then
      coroutine.yield(tag.access .. opts.path_sep .. tag.kind)
    elseif ref then
      coroutine.yield(tag.kind .. opts.path_sep .. ref)
    end

    if tag.signature then
      coroutine.yield(tag.word .. tag.signature)
    end

    coroutine.yield(tag.pattern or tag.word)
  end)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }

  for hit in util.shape(settings, ctx, raw) do
    local lines = vim.iter(doc_iter(settings.clients.tags, ctx, hit.item)):totable()
    if not coroutine.yield(util.item(settings, settings.clients.tags, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = #lines > 0 and { lines = lines, filetype = ctx.filetype } or nil,
    })) then
      return
    end
  end
end

---@return producers.Producer<ctx.full>
M.new = function()
  return producer.threaded {
    idle = function(...)
      require("coq.producers.ctags").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.ctags").matcher(...)
    end,
  }
end

return M
