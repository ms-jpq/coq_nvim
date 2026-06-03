local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local fs_cache = require "coq.lib.fs_cache"
local index_m = require "coq.producers.ctags.index"
local lib = require "coq.lib"
local parse = require "coq.producers.ctags.parse"
local path_fmt = require "coq.producers.path_fmt"
local producer = require "coq.lib.producers"
local run = require "coq.producers.ctags.run"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

local index = util.once(index_m.new)

---@return string
local data_dir = function()
  local xdg = os.getenv "XDG_DATA_HOME"
  if xdg and xdg ~= "" then
    return vim.fs.joinpath(xdg, "nvim", "coq_v2")
  end
  local home = vim.uv.os_homedir() or "."
  return vim.fs.joinpath(home, ".local", "share", "nvim", "coq_v2")
end

local M = {}

---@class ctags.Meta: buf_tracker.Meta
---@field buf integer
---@field filename string

---@param buf integer
---@param prev_mtime? integer
---@return ctags.Meta?
M.buffer_meta = function(buf, prev_mtime)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == "" then
    return nil
  end
  local err, st = atools.fs.stat(filename)
  if err or not st then
    return nil
  end
  local mtime = (st.mtime.sec or 0) * 1000000000 + (st.mtime.nsec or 0)
  if prev_mtime and mtime <= prev_mtime then
    return nil
  end
  return { buf = buf, tick = mtime, filename = filename }
end

---@type table<integer, string>
local filenames_by_buf = {}

local tracker = buf_tracker.new {
  compare = function(buf, previous)
    return worker.main(function(...)
      return require("coq.producers.ctags").buffer_meta(...)
    end, buf, previous and previous.tick)
  end,
  index = function(settings, metas)
    for _, meta in pairs(metas) do
    end
  end,
  prune = lib.noop,
}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker(settings, idle_ctx)
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
  local opts = settings.clients.tags

  local raw = index(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }
  local shaped = util.shape(settings, ctx, raw)

  for hit in shaped do
    local lines = vim.iter(doc_iter(opts, ctx, hit.item)):totable()
    coroutine.yield(util.item(settings, opts, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = #lines > 0 and { lines = lines, filetype = ctx.filetype } or nil,
    }))
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
