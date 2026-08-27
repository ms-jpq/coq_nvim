local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local fs_cache = require "coq.lib.fs_cache"

local index_m = require "coq.producers.tags.index"
local lib = require "coq.lib"
local parse = require "coq.producers.tags.parse"
local path_fmt = require "coq.producers.path_fmt"
local run = require "coq.producers.tags.run"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

local SOURCE = "tags"

local index_of = util.once(index_m.new)

---@type fun(idle_ctx: idle.Ctx): fs_cache.Store<ctags.Tag[]>
local cache_of = util.once(function(idle_ctx)
  return fs_cache.new {
    fs_root = vim.fs.joinpath(idle_ctx.cache_dir, "tags"),
    compute = function(filename)
      local out = run.run("ctags", { filename })
      if not out then
        return nil
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
  atools.scheduled()
  if not vim.api.nvim_buf_is_valid(buf) then
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

  if previous and mtime <= previous.mtime and filename == previous.filename then
    return nil
  end
  return { mtime = mtime, filename = filename }
end

---@type fun(settings: config.Settings): fun(idle_ctx: idle.Ctx)
local tracker_of = util.once(function(settings)
  return buf_tracker.new {
    compare = function(buf, previous)
      return worker.main(function(...)
        return require("coq.producers.tags").buffer_meta(...)
      end, buf, previous)
    end,
    reindex = function(idle_ctx, changes)
      local store = cache_of(idle_ctx)

      local iters = {}
      for _, change in pairs(changes) do
        local iter = function()
          local deleted, prev, curr = unpack(change)
          coroutine.yield {
            deleted = deleted,
            prev = prev,
            curr = curr,
            data = curr ~= nil and store.fetch(curr.filename, curr.mtime) or nil,
          }
        end
        table.insert(iters, async.wrap(iter))
      end

      lib.scope(function(defer)
        local close, stream = async.merge(iters)
        defer(close)

        for _, entry in stream do
          async.sleep(0)
          local prev_name = entry.prev and entry.prev.filename
          local curr_name = entry.curr and entry.curr.filename

          if prev_name and (entry.deleted or prev_name ~= curr_name) then
            index_of(settings).prune { filename = prev_name }
            store.prune(prev_name)
          end

          if curr_name then
            index_of(settings).prune { filename = curr_name }
            for i, tag in ipairs(entry.data or {}) do
              index_of(settings).insert(tag --[[@as ctags.Item]])
              if i % util.BATCH == 0 then
                async.sleep(0)
              end
            end
          end
        end
      end)
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
M.matcher = util.batched(function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search { filetype = ctx.filetype, match_before = ctx.match_before }

  for hit in util.shape(settings, ctx, raw) do
    local item = util.item(settings, SOURCE, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = util.doc(ctx.filetype, doc_iter(settings.clients.tags, ctx, hit.item)),
    })
    if not coroutine.yield(item) then
      return
    end
  end
end)

M.new = util.threaded_module(SOURCE)

return M
