local lib = require "coq.lib"
local threaded = require "coq.lib.producers.threaded"
local tokens = require "coq.lib.index.tokens"

local matcher = function(ctx)
  local index = require "coq.producers.buffer.index"
  for item in index.search(ctx) do
    coroutine.yield { word = item.word, meta = { filter = item.word } }
  end
end

local idle = function(events)
  local index = require "coq.producers.buffer.index"
  for buf, ev in pairs(events) do
    index.prune { buf = buf }

    if ev.kind == "update" then
      local kw = tokens.parse_iskeyword(ev.iskeyword)
      local lines = vim.iter(ev.lines) --[[@as fun(): string?]]
      for word, _ in pairs(tokens.locality(kw, lines)) do
        index.insert { word = word, buf = buf, filetype = ev.filetype }
      end
    end
  end
end

local kinds = {
  BufEnter = "update",
  BufRead = "update",
  BufWinEnter = "update",
  TextChanged = "update",
  TextChangedI = "update",
  BufDelete = "remove",
  BufWipeout = "remove",
}

local M = {}

---@param opts config.BuffersClient
---@return producers.Producer
M.new = function(opts)
  local _ = opts
  return threaded.new {
    key = function(ev)
      return ev.buf
    end,
    idle = idle,
    matcher = matcher,
    bind = function(_, push)
      vim.api.nvim_create_autocmd(vim.tbl_keys(kinds), {
        group = lib.group,
        callback = function(args)
          local buf = args.buf
          local kind = kinds[args.event]
          if kind == "remove" then
            push { kind = "remove", buf = buf }
          elseif kind == "update" and vim.api.nvim_buf_is_loaded(buf) then
            push {
              kind = "update",
              buf = buf,
              lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true),
              filetype = vim.bo[buf].filetype,
              iskeyword = vim.bo[buf].iskeyword,
            }
          end
        end,
      })
    end,
  }
end

return M
