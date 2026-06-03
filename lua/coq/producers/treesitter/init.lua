local async = require "coq.lib.async"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local index_m = require "coq.producers.treesitter.index"
local lib = require "coq.lib"
local path_fmt = require "coq.producers.path_fmt"
local producer = require "coq.lib.producers"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class treesitter.Meta
---@field tick integer
---@field filetype string
---@field filename string

local index_of = util.once(index_m.new)

local M = {}

---@param buf integer
---@param previous? treesitter.Meta
---@return treesitter.Meta?
M.buffer_meta = function(buf, previous)
  if not util.is_live(buf) then
    return nil
  end

  local tick = vim.b[buf].changedtick
  if previous and tick == previous.tick then
    return nil
  end

  return {
    tick = tick,
    filetype = vim.bo[buf].filetype,
    filename = vim.api.nvim_buf_get_name(buf),
  }
end

---@type fun(settings: config.Settings): fun(idle_ctx: idle.Ctx)
local tracker_of = util.once(function(settings)
  return buf_tracker.new {
    compare = function(buf, previous)
      return worker.main(function(...)
        return require("coq.producers.treesitter").buffer_meta(...)
      end, buf, previous)
    end,
    index = function(_, metas)
      for buf, meta in pairs(metas) do
        async.sleep(0)
        lib.scope(function(defer)
          local close, stream = worker.main_stream(function(...)
            return require("coq.producers.treesitter.request").query(...)
          end, buf)
          defer(close)
          for payload in
            stream --[[@as lib.Iterator<treesitter.Payload>]]
          do
            if type(payload.text) == "string" and payload.text ~= "" then
              index_of(settings).insert {
                buf = buf,
                filetype = meta.filetype,
                filename = meta.filename,
                word = payload.text,
                kind = payload.kind,
                range = payload.range,
                parent = payload.parent,
                grandparent = payload.grandparent,
              }
            end
          end
        end)
      end
    end,
    prune = function(_, stale)
      for buf in pairs(stale) do
        index_of(settings).prune { buf = buf }
      end
    end,
  }
end)

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker_of(settings)(idle_ctx)
end

---@param kind string
---@return string
local capture_to_icon = function(kind)
  local head = string.match(kind, "^[^.]+") or ""
  if head == "" then
    return ""
  end
  return string.upper(string.sub(head, 1, 1)) .. string.sub(head, 2)
end

---@param clhs string
---@param crhs string
---@param kind string
---@param text string
local section_iter = function(clhs, crhs, kind, text)
  return coroutine.wrap(function()
    coroutine.yield(clhs .. kind)

    local pending = nil
    for line in txt.splitlines(text) do
      if pending ~= nil then
        coroutine.yield(pending)
      end
      pending = line
    end

    if pending ~= nil then
      coroutine.yield(pending .. crhs)
    end
  end)
end

---@param opts config.TSClient
---@param ctx ctx.full
---@param item treesitter.Item
---@return lib.Iterator<string>
local doc_iter = function(opts, ctx, item)
  return coroutine.wrap(function()
    local clhs, crhs = unpack(ctx.comment)
    local r_lo, r_hi = unpack(item.range)

    local pos = path_fmt.fmt(ctx.cwd, item.filename, ctx.filename)
    local range_str = ":" .. r_lo .. (r_hi ~= r_lo and ("-" .. r_hi) or "")
    coroutine.yield(clhs .. pos .. range_str .. opts.path_sep .. crhs)

    if item.grandparent then
      for line in section_iter(clhs, crhs, item.grandparent.kind, item.grandparent.text) do
        coroutine.yield(line)
      end
    end

    if item.grandparent and item.parent then
      coroutine.yield(clhs .. opts.path_sep .. crhs)
    end

    if item.parent then
      for line in section_iter(clhs, crhs, item.parent.kind, item.parent.text) do
        coroutine.yield(line)
      end
    end
  end)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }

  for hit in util.shape(settings, ctx, raw) do
    local lines = vim.iter(doc_iter(settings.clients.tree_sitter, ctx, hit.item)):totable()
    if not coroutine.yield(util.item(settings, settings.clients.tree_sitter, {
      word = hit.item.word,
      kind = capture_to_icon(hit.item.kind),
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = { lines = lines, filetype = ctx.filetype },
    })) then
      return
    end
  end
end

---@return producers.Producer<ctx.full>
M.new = function()
  return producer.threaded {
    idle = function(...)
      require("coq.producers.treesitter").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.treesitter").matcher(...)
    end,
  }
end

return M
