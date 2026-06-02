local async = require "coq.lib.async"
local fs = require "coq.producers.fs"
local index = require "coq.producers.tags.index"
local parse = require "coq.producers.tags.parse"
local producer = require "coq.lib.producers"
local run = require "coq.producers.tags.run"
local util = require "coq.producers.util"

local MAX_BYTES = 1024 * 1024

local M = {}

local mtimes = {}

---@param _ config.Settings
---@param events table<string, 'update' | 'remove'>
M.idle = function(_, events)
  local stale = {}

  for path, kind in pairs(events) do
    async.sleep(0)
    if kind == "remove" then
      index.prune { path = path }
      mtimes[path] = nil
    else
      local st = vim.uv.fs_stat(path)
      if st and st.size <= MAX_BYTES and (st.mtime.sec or 0) > (mtimes[path] or 0) then
        index.prune { path = path }
        mtimes[path] = st.mtime.sec or 0
        table.insert(stale, path)
      end
    end
  end

  if #stale == 0 then
    return
  end

  local raw = run.run("ctags", stale)
  if raw == nil then
    return
  end

  for tag in parse.parse(raw) do
    async.sleep(0)
    index.insert(tag)
  end
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
      coroutine.yield(tag.name .. tag.signature)
    end

    coroutine.yield(tag.pattern or tag.name)
  end)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.tags
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]

  local search_ctx = {
    language = ctx.filetype,
    keyword_before = ctx.keyword_before,
  }

  for tag in
    index.search(search_ctx) --[[@as lib.Iterator<tags.Item>]]
  do
    if tag.name ~= ctx.cword then
      local lines = vim.iter(doc_iter(opts, ctx, tag)):totable()
      coroutine.yield {
        word = tag.name,
        kind = "Text",
        menu = menu,
        meta = {
          filter = tag.name,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
          doc = #lines > 0 and { lines = lines, filetype = ctx.filetype } or nil,
        },
      }
    end
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  local pending = {}
  local path_by_buf = {}

  return producer.threaded {
    settings = settings,
    max_pulls = settings.clients.tags.max_pulls or math.huge,
    bind = function(n)
      util.buffer_bind(n, function(buf, kind)
        local path
        if kind == "update" then
          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end
          path = vim.api.nvim_buf_get_name(buf)
          if path == "" then
            return
          end
          path_by_buf[buf] = path
        else
          path = path_by_buf[buf]
          if path == nil then
            return
          end
          path_by_buf[buf] = nil
        end
        pending[path] = kind
      end)
    end,
    drain = function()
      local p = pending
      pending = {}
      return p
    end,
    idle = function(...)
      require("coq.producers.tags").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.tags").matcher(...)
    end,
  }
end

return M
