local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local fs = require "coq.producers.fs"
local index = require "coq.producers.treesitter.index"
local threaded = require "coq.lib.producers.threaded"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@class treesitter.BufMeta
---@field buf integer
---@field tick integer
---@field filetype string
---@field filename string

---@class treesitter.State
---@field last_tick table<integer, integer>

local M = {
  ---@type treesitter.State
  state = { last_tick = {} },
}

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

---@param buf integer
local update_buf = function(buf)
  local meta = worker.main(function(...)
    return require("coq.producers.treesitter").buffer_meta(...)
  end, buf, M.state.last_tick[buf])

  if not meta then
    return
  end

  M.state.last_tick[meta.buf] = meta.tick
  index.prune { buf = meta.buf }

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
end

M.idle = function(_, events)
  for buf, ev in pairs(events) do
    async.sleep(0)

    if ev.kind == "remove" then
      index.prune { buf = buf }
      M.state.last_tick[buf] = nil
    elseif ev.kind == "update" then
      update_buf(buf)
    end
  end
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

---@param opts config.TSClient
---@param ctx ctx.full
---@param item treesitter.Item
---@return string
local doc = function(opts, ctx, item)
  local parts = {}

  local pos = fs.fmt_path(ctx.cwd, item.filename, ctx.filename)
  local r_lo, r_hi = item.range[1], item.range[2]
  local range_str = ":" .. r_lo .. (r_hi ~= r_lo and ("-" .. r_hi) or "")
  table.insert(parts, pos .. range_str)

  if item.grandparent then
    table.insert(parts, item.grandparent.kind)
    table.insert(parts, item.grandparent.text)
  end

  if item.grandparent and item.parent then
    table.insert(parts, opts.path_sep)
  end

  if item.parent then
    table.insert(parts, item.parent.kind)
    table.insert(parts, item.parent.text)
  end

  return table.concat(parts, "\n")
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.tree_sitter
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]

  local items = util.dedup(
    index.search { filetype = ctx.filetype, keyword_before = ctx.keyword_before } --[[@as lib.Iterator<treesitter.Item>]],
    function(it)
      return it.text
    end
  )

  for item in items do
    if item.text ~= ctx.cword then
      coroutine.yield {
        word = item.text,
        kind = capture_to_icon(item.kind),
        menu = menu,
        info = doc(opts, ctx, item),
        meta = {
          filter = item.text,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
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
