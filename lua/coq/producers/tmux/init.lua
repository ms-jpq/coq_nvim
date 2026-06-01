local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local index = require "coq.producers.tmux.index"
local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"
local util = require "coq.producers.util"

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

local M = {}

---@param _ async.Nursery
---@param push producers.Push
local bind = function(_, push)
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = lib.group,
    callback = function(args)
      push { kind = "iskeyword", iskeyword = vim.bo[args.buf].iskeyword }
    end,
  })
  vim.api.nvim_create_autocmd({ "FocusGained" }, {
    group = lib.group,
    callback = function()
      push { kind = "focus" }
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

---@param pane string
---@return string?
local pane_capture = function(pane)
  local proc = atools.spawn { "tmux", "capture-pane", "-p", "-J", "-t", pane }
  if proc == nil or proc.code ~= 0 then
    return nil
  end
  return proc.stdout
end

do
  local cache = {}
  ---@type string?
  local iskeyword

  ---@param kw table<integer, true>
  ---@param pane tmux.Pane
  ---@param text string
  local reindex_pane = function(kw, pane, text)
    if cache[pane.id] == text then
      return
    end
    async.sleep(0)

    index.prune { pane = pane.id }
    for word in tokens.words(kw, vim.gsplit(text, "\n", { plain = true })) do
      index.insert { pane = pane.id, word = word, meta = pane.meta }
    end
    cache[pane.id] = text
  end

  ---@param settings config.Settings
  M.idle = function(settings, events)
    for _, ev in pairs(events) do
      if ev.kind == "iskeyword" then
        iskeyword = ev.iskeyword
      end
    end

    local env = vim.uv.os_environ()
    if env.TMUX == nil or iskeyword == nil then
      return
    end

    local kw = tokens.parse_iskeyword(iskeyword)

    local panes, live = {}, {}
    for pane in list_panes(settings, env.TMUX_PANE) do
      table.insert(panes, pane)
      live[pane.id] = true
    end

    for id in pairs(cache) do
      if not live[id] then
        index.prune { pane = id }
        cache[id] = nil
      end
    end

    local captures = async.all(vim.tbl_map(function(pane)
      return function()
        return pane_capture(pane.id)
      end
    end, panes))

    for i, pane in pairs(panes) do
      local text = captures[i]
      if text ~= nil then
        reindex_pane(kw, pane, text)
      end
    end
  end
end

---@param opts config.TmuxClient
---@param meta tmux.PaneMeta
---@return lib.Iterator<string>
local doc_iter = function(opts, meta)
  return async.wrap(function()
    if opts.all_sessions then
      coroutine.yield("S: " .. meta.session_name .. opts.parent_scope)
    end
    coroutine.yield("W: #" .. meta.window_index .. opts.path_sep .. meta.window_name .. opts.parent_scope)
    coroutine.yield("P: #" .. meta.pane_index .. opts.path_sep .. meta.pane_title)
  end)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.tmux
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]

  local items = util.dedup(index.search(ctx) --[[@as lib.Iterator<tmux.Item>]], function(it)
    return it.word
  end)
  for item in items do
    if item.word ~= ctx.cword then
      local lines = vim.iter(doc_iter(opts, item.meta)):totable()
      coroutine.yield {
        word = item.word,
        kind = "Text",
        menu = menu,
        meta = {
          filter = item.word,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
          doc = #lines > 0 and { lines = lines, filetype = "" } or nil,
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
