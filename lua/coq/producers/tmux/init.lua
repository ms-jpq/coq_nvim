local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"

local SEP = "\30"
local PANE_FMT = "#{pane_id}" .. SEP .. "#{pane_active}"

local matcher = function(ctx)
  local index = require "coq.producers.tmux.index"
  for item in index.search(ctx) do
    coroutine.yield { word = item.word, meta = { filter = item.word } }
  end
end

---@param exclude string?
---@return lib.Iterator<string>
local list_panes = function(exclude)
  return async.wrap(function()
    local proc = atools.spawn { "tmux", "list-panes", "-s", "-F", PANE_FMT }
    if proc == nil or proc.code ~= 0 then
      return
    end
    for line in vim.gsplit(proc.stdout, "\n", { plain = true }) do
      local id = string.match(line, "^(.-)" .. SEP)
      if id ~= nil and id ~= exclude then
        coroutine.yield(id)
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

local idle = function(events)
  local state = require "coq.producers.tmux.state"

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

  for pane in list_panes(env.TMUX_PANE) do
    index.prune { pane = pane }
    for word in pane_words(kw, pane) do
      index.insert { pane = pane, word = word }
    end
  end
end

local M = {}

---@param opts config.TmuxClient
---@return producers.Producer
M.new = function(opts)
  local _ = opts
  return threaded.new {
    key = function(ev)
      return ev.kind
    end,
    idle = idle,
    matcher = matcher,
    bind = function(_, push)
      vim.api.nvim_create_autocmd({ "BufEnter" }, {
        group = lib.group,
        callback = function(args)
          push { kind = "iskeyword", iskeyword = vim.bo[args.buf].iskeyword }
        end,
      })
    end,
  }
end

return M
