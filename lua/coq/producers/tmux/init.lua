local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"

local SEP = "\30"
local PANE_FIELDS = {
  "#{pane_id}",
  "#{session_name}",
  "#{window_index}",
  "#{window_name}",
  "#{pane_index}",
  "#{pane_title}",
}
local PANE_FMT = table.concat(PANE_FIELDS, SEP)

---@class tmux.Pane
---@field id string
---@field meta tmux.PaneMeta

---@class tmux.State
---@field iskeyword? string
---@field panes table<string, true>

local M = {
  ---@type tmux.State
  state = { panes = {} },
}

---@param _ async.Nursery
---@param push producers.Push
local bind = function(_, push)
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = lib.group,
    callback = function(args)
      push { kind = "iskeyword", iskeyword = vim.bo[args.buf].iskeyword }
    end,
  })

  push { kind = "iskeyword", iskeyword = vim.bo.iskeyword }
end

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
    for line in vim.gsplit(proc.stdout, "\n", { plain = true }) do
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

---@param kw table<integer, true>
---@param pane string
---@return lib.Iterator<string>
local pane_words = function(kw, pane)
  return async.wrap(function()
    local proc = atools.spawn { "tmux", "capture-pane", "-p", "-J", "-t", pane }
    if proc == nil or proc.code ~= 0 then
      return
    end
    local lines = vim.iter(vim.split(proc.stdout, "\n", { plain = true })) --[[@as fun(): string?]]
    for word in tokens.words(kw, lines) do
      coroutine.yield(word)
    end
  end)
end

---@param settings config.Settings
M.idle = function(settings, events)
  local state = require("coq.producers.tmux").state

  for _, ev in pairs(events) do
    if ev.kind == "iskeyword" then
      state.iskeyword = ev.iskeyword
    end
  end

  local env = vim.uv.os_environ()
  if env.TMUX == nil or state.iskeyword == nil then
    return
  end

  local kw = tokens.parse_iskeyword(state.iskeyword)
  local index = require "coq.producers.tmux.index"

  local live = {}
  for pane in list_panes(settings, env.TMUX_PANE) do
    live[pane.id] = pane
  end

  for id in pairs(state.panes) do
    if not live[id] then
      index.prune { pane = id }
    end
  end

  state.panes = {}
  for id, pane in pairs(live) do
    index.prune { pane = id }
    for word in pane_words(kw, id) do
      index.insert { pane = id, word = word, meta = pane.meta }
    end
    state.panes[id] = true
  end
end

---@param opts config.TmuxClient
---@param meta tmux.PaneMeta
---@return string
local doc = function(opts, meta)
  local parts = {}
  if opts.all_sessions then
    table.insert(parts, "S: " .. meta.session_name .. opts.parent_scope)
  end
  table.insert(parts, "W: #" .. meta.window_index .. opts.path_sep .. meta.window_name .. opts.parent_scope)
  table.insert(parts, "P: #" .. meta.pane_index .. opts.path_sep .. meta.pane_title)
  return table.concat(parts, "\n")
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.tmux
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]
  local index = require "coq.producers.tmux.index"
  for item in
    index.search(ctx) --[[@as fun(): tmux.Item?]]
  do
    if item.word ~= ctx.cword then
      coroutine.yield {
        word = item.word,
        kind = "Text",
        menu = menu,
        info = item.meta ~= nil and doc(opts, item.meta) or nil,
        meta = {
          filter = item.word,
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
    max_pulls = settings.clients.tmux.max_pulls,
    key = function(ev)
      return ev.kind
    end,
    bind = bind,
    idle = function(...)
      require("coq.producers.tmux").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.tmux").matcher(...)
    end,
  }
end

return M
