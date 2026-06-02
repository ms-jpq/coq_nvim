local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buf_tracker = require "coq.lib.producers.buf_tracker"
local fs = require "coq.producers.fs"
local index = require "coq.producers.treesitter.index"
local threaded = require "coq.lib.producers.threaded"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class treesitter.BufMeta : buf_tracker.Meta
---@field buf integer
---@field filetype string
---@field filename string

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
  reindex = function(meta)
    for payload in
      worker.main_stream(function(...)
        return require("coq.producers.treesitter.request").query(...)
      end, meta.buf) --[[@as lib.Iterator<treesitter.Payload>]]
    do
      index.insert {
        buf = meta.buf,
        filetype = meta.filetype,
        filename = meta.filename,
        text = payload.text,
        kind = payload.kind,
        range = payload.range,
        parent = payload.parent,
        grandparent = payload.grandparent,
      }
    end
  end,
  prune = function(buf)
    index.prune { buf = buf }
  end,
}

M.idle = tracker.idle

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
    for line in vim.gsplit(text, "\n", { plain = true }) do
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
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]

  for item in
    index.search { filetype = ctx.filetype, keyword_before = ctx.keyword_before } --[[@as lib.Iterator<treesitter.Item>]]
  do
    if item.text ~= ctx.cword then
      local lines = vim.iter(doc_iter(opts, ctx, item)):totable()
      coroutine.yield {
        word = item.text,
        kind = capture_to_icon(item.kind),
        menu = menu,
        meta = {
          filter = item.text,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
          doc = { lines = lines, filetype = ctx.filetype },
        },
      }
    end
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return threaded.new {
    settings = settings,
    max_pulls = settings.clients.tree_sitter.max_pulls,
    key = util.buffer_key,
    bind = util.buffer_bind,
    idle = function(...)
      require("coq.producers.treesitter").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.treesitter").matcher(...)
    end,
  }
end

return M
