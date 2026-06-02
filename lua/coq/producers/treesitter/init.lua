local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local fs = require "coq.producers.fs"
local index_m = require "coq.producers.treesitter.index"
local producer = require "coq.lib.producers"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class treesitter.BufMeta : buf_tracker.Meta
---@field buf integer
---@field filetype string
---@field filename string

local index = util.once(index_m.new)

local M = {}

---@param buf integer
---@param prev_tick? integer
---@return treesitter.BufMeta?
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
  fetch = function(buf, prev_tick)
    return worker.main(function(...)
      return require("coq.producers.treesitter").buffer_meta(...)
    end, buf, prev_tick)
  end,
  reindex = function(settings, metas)
    for _, meta in pairs(metas) do
      async.sleep(0)
      for payload in
        worker.main_stream(function(...)
          return require("coq.producers.treesitter.request").query(...)
        end, meta.buf) --[[@as lib.Iterator<treesitter.Payload>]]
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
  return async.wrap(function()
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
  return async.wrap(function()
    local clhs, crhs = ctx.comment[1], ctx.comment[2]

    local pos = fs.fmt_path(ctx.cwd, item.filename, ctx.filename)
    local r_lo, r_hi = item.range[1], item.range[2]
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
  local menu = util.menu(settings, opts)

  local raw = index(settings).search { filetype = ctx.filetype, keyword_before = ctx.keyword_before }
  local shaped = util.shape(settings, ctx, raw)

  for item in shaped do
    local lines = vim.iter(doc_iter(opts, ctx, item)):totable()
    coroutine.yield(util.item(opts, {
      word = item.word,
      kind = capture_to_icon(item.kind),
      menu = menu,
      filter = item.word,
      doc = { lines = lines, filetype = ctx.filetype },
    }))
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return producer.threaded {
    settings = settings,
    idle = function(...)
      require("coq.producers.treesitter").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.treesitter").matcher(...)
    end,
  }
end

return M
