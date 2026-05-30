local mpmc = require "coq.lib.channels.mpmc"
local threaded = require "coq.lib.producers.threaded"

local POLL_MS = 5000

local matcher = function(ctx)
  local index = require "coq.producers.tmux.index"
  for item in index.search(ctx) do
    coroutine.yield { word = item.word, meta = { filter = item.word } }
  end
end

local idle = function(events)
  local index = require "coq.producers.tmux.index"

  for _, ev in ipairs(events) do
    if ev.kind == "remove" then
      index.prune { pane = ev.pane }
    elseif ev.kind == "update" then
      index.prune { pane = ev.pane }
      for _, word in ipairs(ev.words) do
        index.insert { word = word, pane = ev.pane }
      end
    end
  end
end

---@param text string
---@return string[]
local tokenize = function(text)
  local seen, words = {}, {}
  for word in string.gmatch(text, "[%w_]+") do
    if not seen[word] then
      seen[word] = true
      table.insert(words, word)
    end
  end
  return words
end

local SEP = "\30"
local PANE_FMT = table.concat({ "#{pane_id}", "#{pane_active}" }, SEP)

---@param cb fun(panes: { id: string, active: boolean }[])
local list_panes = function(cb)
  vim.system({ "tmux", "list-panes", "-s", "-F", PANE_FMT }, { text = true }, function(obj)
    if obj.code ~= 0 then
      return cb {}
    end
    local panes = {}
    for line in string.gmatch(obj.stdout, "[^\n]+") do
      local id, active = string.match(line, "^(.-)" .. SEP .. "(.-)$")
      if id then
        table.insert(panes, { id = id, active = active == "1" })
      end
    end
    cb(panes)
  end)
end

---@param pane_id string
---@param cb fun(text: string)
local capture_pane = function(pane_id, cb)
  vim.system({ "tmux", "capture-pane", "-p", "-J", "-t", pane_id }, { text = true }, function(obj)
    cb(obj.code == 0 and obj.stdout or "")
  end)
end

local M = {}

---@param opts config.TmuxClient
---@return producers.Producer
M.new = function(opts)
  local _ = opts
  return threaded.new {
    idle = idle,
    matcher = matcher,
    bind = function(n, push)
      if vim.env.TMUX == nil then
        return
      end
      local current = vim.env.TMUX_PANE
      local chan = mpmc.new(nil, n.handle)

      local poll = function()
        list_panes(function(panes)
          for _, pane in ipairs(panes) do
            if pane.id ~= current then
              capture_pane(pane.id, function(text)
                chan.push { pane = pane.id, text = text }
              end)
            end
          end
        end)
      end

      local timer = vim.uv.new_timer()
      if not timer then
        return
      end
      timer:start(0, POLL_MS, vim.schedule_wrap(poll))

      local _ = n.handle.on_cancel(function()
        if not timer:is_closing() then
          timer:stop()
          timer:close()
        end
      end)

      n.spawn(function()
        for item in chan do
          push { kind = "update", pane = item.pane, words = tokenize(item.text) }
        end
      end)
    end,
  }
end

return M
