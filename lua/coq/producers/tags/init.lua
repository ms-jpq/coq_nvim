local async = require "coq.lib.async"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local fs = require "coq.producers.fs"
local index_m = require "coq.producers.tags.index"
local parse = require "coq.producers.tags.parse"
local producer = require "coq.lib.producers"
local run = require "coq.producers.tags.run"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

local index = util.once(index_m.new)

local M = {}

---@class tags.Info: buf_tracker.Meta
---@field buf integer
---@field path string

---@param buf integer
---@param prev_mtime? integer
---@return tags.Info?
M.buffer_info = function(buf, prev_mtime)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return nil
  end
  local st = vim.uv.fs_stat(path)
  if not st then
    return nil
  end
  local mtime = st.mtime.sec or 0
  if prev_mtime and mtime <= prev_mtime then
    return nil
  end
  return { buf = buf, tick = mtime, path = path }
end

local tracker = buf_tracker.new {
  fetch = function(buf, prev_mtime)
    return worker.main(function(...)
      return require("coq.producers.tags").buffer_info(...)
    end, buf, prev_mtime)
  end,
  reindex = function(settings, infos)
    local paths = vim.tbl_map(function(i)
      return i.path
    end, infos)
    local raw = run.run("ctags", paths)
    if raw == nil then
      return
    end

    local buf_by_path = {}
    for _, i in pairs(infos) do
      buf_by_path[i.path] = i.buf
    end

    for tag in parse.parse(raw) do
      async.sleep(0)
      local buf = buf_by_path[tag.path]
      if buf then
        ---@diagnostic disable-next-line: inject-field
        tag.buf = buf
        index(settings).insert(tag --[[@as tags.Item]])
      end
    end
  end,
  prune = function(settings, buf)
    index(settings).prune { buf = buf }
  end,
}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker(settings, idle_ctx)
end

---@param opts config.TagsClient
---@param ctx ctx.full
---@param tag tags.Item
---@return lib.Iterator<string>
local doc_iter = function(opts, ctx, tag)
  return async.wrap(function()
    coroutine.yield(fs.fmt_path(ctx.cwd, tag.path, ctx.filename) .. ":" .. tag.line)

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
  local menu = util.menu(settings, opts)

  local raw = index(settings).search { keyword_before = ctx.keyword_before }
  local shaped = util.shape(settings, ctx, raw)

  for tag in shaped do
    local lines = vim.iter(doc_iter(opts, ctx, tag)):totable()
    coroutine.yield(util.item(opts, {
      word = tag.word,
      kind = "Text",
      menu = menu,
      filter = tag.word,
      doc = #lines > 0 and { lines = lines, filetype = ctx.filetype } or nil,
    }))
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return producer.threaded {
    settings = settings,
    idle = function(...)
      require("coq.producers.tags").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.tags").matcher(...)
    end,
  }
end

return M
