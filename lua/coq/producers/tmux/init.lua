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

local idle = function(events)
  local state = require "coq.producers.tmux.state"
  for _, ev in pairs(events) do
    if ev.kind == "iskeyword" then
      state.iskeyword = ev.iskeyword
    elseif ev.kind == "tmux" then
      state.tmux = ev.tmux
      state.tmux_pane = ev.tmux_pane
    end
  end

  if state.tmux == nil or state.iskeyword == nil then
    return
  end

  local list_result = atools.spawn { "tmux", "list-panes", "-s", "-F", PANE_FMT }
  if list_result == nil or list_result.code ~= 0 then
    return
  end

  local panes = {}
  for line in string.gmatch(list_result.stdout, "[^\n]+") do
    local id = string.match(line, "^(.-)" .. SEP)
    if id ~= nil and id ~= state.tmux_pane then
      table.insert(panes, id)
    end
  end

  local kw = tokens.parse_iskeyword(state.iskeyword)
  local index = require "coq.producers.tmux.index"
  for _, pane in ipairs(panes) do
    index.prune { pane = pane }
    local capture = atools.spawn { "tmux", "capture-pane", "-p", "-J", "-t", pane }
    if capture ~= nil and capture.code == 0 then
      local lines = vim.iter(vim.split(capture.stdout, "\n", { plain = true })) --[[@as fun(): string?]]
      for word, _ in pairs(tokens.locality(kw, lines)) do
        index.insert { word = word, pane = pane }
      end
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
      push { kind = "tmux", tmux = vim.env.TMUX, tmux_pane = vim.env.TMUX_PANE }

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
