local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local match = require "coq.lib.index.rank.match"
local parse = require "coq.producers.fullpaths.parse"
local path = require "coq.lib.path"
local util = require "coq.producers.util"
local wildignore = require "coq.producers.paths.wildignore"

local M = {
  source = "fullpaths",
}

---@class fullpaths.Match
---@field full string
---@field relative string
---@field fuzzy number

---@param root string
---@param ignores string[]
---@param cand fullpaths.parse.Candidate
---@return lib.Iterator<fullpaths.Match>
local scan_root = function(root, ignores, cand)
  return async.wrap(function()
    lib.scope(function(defer)
      local close, files = atools.fs.walk(root)
      defer(close)

      for i, full, kind in vim.iter(files):enumerate() do
        local relative = vim.fs.relpath(root, full)
        if kind == "file" and relative and not wildignore.is_ignored(ignores, vim.fs.basename(full), full) then
          relative = string.gsub(relative, "/", cand.local_sep)
          local score = cand.partial == "" and 0 or match.score(cand.partial, relative)
          if cand.partial == "" or score > 0 then
            coroutine.yield { full = full, relative = relative, fuzzy = score }
          end
        end
        if i % util.BATCH == 0 then
          async.sleep(0)
        end
      end
    end)
  end)
end

---@param settings config.Settings
---@param ctx ctx.full
---@param cand fullpaths.parse.Candidate
---@return fun() close
---@return fun(): integer, fullpaths.Match iter
local matches = function(settings, ctx, cand)
  local ignores = wildignore.compile(ctx.wildignore)
  local walks = vim
    .iter(path.bases(settings.clients.fullpaths.resolution, ctx))
    :unique()
    :map(function(root)
      return scan_root(root, ignores, cand)
    end)
    :totable()
  return async.merge(walks)
end

---@param settings config.Settings
---@param ctx ctx.full
M.matcher = util.batched(function(settings, ctx)
  local symbol = settings.clients.fullpaths.symbol
  local cand = parse.candidate(ctx.line_before, { symbol = symbol, is_windows = lib.is_windows })
  if cand == nil then
    return
  end
  local row, col = unpack(ctx.pos)

  lib.scope(function(defer)
    local close, iter = matches(settings, ctx, cand)
    defer(close)

    for _, m in iter do
      local word = symbol .. m.relative
      local item = util.item(settings, M.source, {
        word = word,
        kind = "File",
        filter = m.relative,
        fuzzy = m.fuzzy,
        path = m.full,
        lsp = {
          position_encoding = "utf-8",
          item = {
            label = word,
            textEdit = {
              range = {
                start = { line = row - 1, character = cand.start },
                ["end"] = { line = row - 1, character = col + #word - #ctx.keyword_before },
              },
              newText = word,
            },
          },
        },
      })
      if not coroutine.yield(item) then
        return
      end
    end
  end)
end)

M.idle = lib.noop

M.new = util.threaded_module(M.source)

return M
