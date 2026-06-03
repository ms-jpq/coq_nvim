local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local index_m = require "coq.producers.treesitter.index"
local lib = require "coq.lib"
local path_fmt = require "coq.producers.path_fmt"
local producer = require "coq.lib.producers"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class treesitter.Meta : buf_tracker.Meta
---@field buf integer
---@field filetype string
---@field filename string

local index = util.once(index_m.new)

local M = {}

---@param buf integer
---@param prev_tick? integer
---@return treesitter.Meta?
M.buffer_meta = function(buf, prev_tick)
  atools.scheduled()
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end

  local tick = vim.b[buf].changedtick
  if tick == prev_tick then
    return nil
  end

  return {
    buf = buf,
    tick = tick,
    filetype = vim.bo[buf].filetype,
    filename = vim.api.nvim_buf_get_name(buf),
  }
end

local tracker = buf_tracker.new {
  compare = function(buf, previous)
    return worker.main(function(...)
      return require("coq.producers.treesitter").buffer_meta(...)
    end, buf, previous and previous.tick)
  end,
  index = function(settings, metas)
    for _, meta in pairs(metas) do
      async.sleep(0)
      lib.scope(function(defer)
        local close, stream = worker.main_stream(function(...)
          return require("coq.producers.treesitter.request").query(...)
        end, meta.buf)
        defer(close)
        for payload in
          stream --[[@as lib.Iterator<treesitter.Payload>]]
        do
          if type(payload.text) == "string" and payload.text ~= "" then
            index(settings).insert {
              buf = meta.buf,
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
  prune = function(settings, bufs)
    for _, buf in pairs(bufs) do
      index(settings).prune { buf = buf }
    end
  end,
}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  tracker(settings, idle_ctx)
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
  local opts = settings.clients.tree_sitter

  local raw = index(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }
  local shaped = util.shape(settings, ctx, raw)

  for hit in shaped do
    local lines = vim.iter(doc_iter(opts, ctx, hit.item)):totable()
    coroutine.yield(util.item(settings, opts, {
      word = hit.item.word,
      kind = capture_to_icon(hit.item.kind),
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = { lines = lines, filetype = ctx.filetype },
    }))
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
