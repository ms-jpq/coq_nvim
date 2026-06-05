local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local index_m = require "coq.producers.tmux.index"
local lib = require "coq.lib"
local tokens = require "coq.lib.index.tokens"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"

local SOURCE = "tmux"

local TMUX_PANE = vim.uv.os_environ().TMUX_PANE

local SEP = "\30"
local PANE_FMT = table.concat({
  "#{pane_id}",
  "#{session_name}",
  "#{window_index}",
  "#{window_name}",
  "#{pane_index}",
  "#{pane_title}",
}, SEP)

---@class tmux.Pane
---@field id string
---@field meta tmux.PaneMeta

local index_of = util.once(index_m.new)

local M = {}

---@param settings config.Settings
---@param exclude string?
---@return lib.Iterator<tmux.Pane>
local list_panes = function(settings, exclude)
  return async.wrap(function()
    local scope_arg = settings.clients.tmux.all_sessions and "-a" or "-s"
    local proc = atools.spawn { "tmux", "list-panes", scope_arg, "-F", PANE_FMT }
    if proc == nil or proc.code ~= 0 then
      return
    end
    for line in txt.splitlines(proc.stdout) do
      if line ~= "" then
        local parts = vim.split(line, SEP, { plain = true })
        local id = parts[1]
        if id ~= nil and id ~= exclude then
          coroutine.yield {
            id = id,
            meta = {
              session_name = parts[2] or "",
              window_index = parts[3] or "",
              window_name = parts[4] or "",
              pane_index = parts[5] or "",
              pane_title = parts[6] or "",
            },
          }
        end
      end
    end
  end)
end

---@param pane string
---@return string?
local pane_capture = function(pane)
  local proc = atools.spawn { "tmux", "capture-pane", "-p", "-J", "-t", pane }
  if proc == nil or proc.code ~= 0 then
    return nil
  end
  return proc.stdout
end

---@class tmux.Work
---@field id string
---@field pane tmux.Pane
---@field text string?

---@param settings config.Settings
---@param cache table<string, string>
---@return table<string, true> removed
---@return (fun(): tmux.Work?)[] iters
local diff_panes = function(settings, cache)
  local live = {}
  for pane in list_panes(settings, TMUX_PANE) do
    live[pane.id] = pane
  end

  local removed = {}
  for id in pairs(cache) do
    if not live[id] then
      removed[id] = true
    end
  end

  local iters = {}
  for id, pane in pairs(live) do
    table.insert(
      iters,
      async.wrap(function()
        coroutine.yield { id = id, pane = pane, text = pane_capture(id) }
      end)
    )
  end

  return removed, iters
end

do
  local cache = {}

  ---@param settings config.Settings
  ---@param idle_ctx idle.Ctx
  M.idle = function(settings, idle_ctx)
    if TMUX_PANE == nil then
      return
    end

    local removed, iters = diff_panes(settings, cache)

    lib.scope(function(defer)
      local close, stream = async.merge(iters)
      defer(close)

      for id in pairs(removed) do
        async.sleep(0)
        index_of(settings).prune { pane = id }
        cache[id] = nil
      end

      for _, entry in stream do
        async.sleep(0)
        if entry.text ~= nil and entry.text ~= cache[entry.id] then
          index_of(settings).prune { pane = entry.id }
          if entry.text ~= "" then
            for word in
              tokens.keywords(idle_ctx.ctx.iskeyword, vim.iter { entry.text } --[[@as lib.Iterator<string>]])
            do
              index_of(settings).insert { pane = entry.id, word = word, meta = entry.pane.meta }
            end
          end
          cache[entry.id] = entry.text
        end
      end
    end)
  end
end

---@param opts config.TmuxClient
---@param meta tmux.PaneMeta
---@return lib.Iterator<string>
local doc_iter = function(opts, meta)
  return coroutine.wrap(function()
    if opts.all_sessions then
      coroutine.yield("S: " .. meta.session_name .. opts.parent_scope)
    end
    coroutine.yield("W: #" .. meta.window_index .. opts.path_sep .. meta.window_name .. opts.parent_scope)
    coroutine.yield("P: #" .. meta.pane_index .. opts.path_sep .. meta.pane_title)
  end)
end

---@param settings config.Settings
M.matcher = util.batched(function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search { keyword_before = ctx.keyword_before }

  for hit in util.shape(settings, ctx, raw) do
    local item = util.item(settings, SOURCE, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      doc = util.doc("", doc_iter(settings.clients.tmux, hit.item.meta)),
    })
    if not coroutine.yield(item) then
      return
    end
  end
end)

M.new = util.threaded_module(SOURCE)

return M
