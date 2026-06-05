local closable = require "coq.lib.closable"
local errs = require "coq.lib.errs"
local lib = require "coq.lib"
local parsers = require "coq.producers.snippets.parsers"
local sources = require "coq.producers.snippets.sources"

---@param src snippets.Source
---@return snippets.Extends extends
---@return snippets.Sourced sourced
local parse = function(src)
  local err, extends, sourced = parsers.parse(src)
  if err then
    errs.report(err)
  end
  return extends, sourced
end

---@class snippets.Loader
---@field sources fun(): table<string, snippets.Source[]>
---@field extends fun(): snippets.Extends[]
---@field parse fun(filetype: string): fun(), lib.Iterator<snippets.Item>

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@return snippets.Loader
M.new = function(settings, idle_ctx)
  ---@diagnostic disable-next-line: missing-fields
  local loader = {} ---@type snippets.Loader

  loader.sources = function()
    local acc = {}
    lib.scope(function(defer)
      local close, iter = sources.list(settings, idle_ctx)
      defer(close)
      for src in iter do
        local _, sourced = parse(src)
        for _, ft in pairs(sourced.filetypes) do
          acc[ft] = acc[ft] or {}
          table.insert(acc[ft], src)
        end
      end
    end)
    return acc
  end

  loader.extends = function()
    ---@type snippets.Extends[]
    local all = {}
    lib.scope(function(defer)
      local close, iter = sources.list(settings, idle_ctx)
      defer(close)
      for src in iter do
        local extends, _ = parse(src)
        table.insert(all, extends)
      end
    end)
    return all
  end

  loader.parse = function(filetype)
    return closable.iter(function(defer)
      local close, iter = sources.list(settings, idle_ctx)
      defer(close)
      for src in iter do
        local _, sourced = parse(src)
        if vim.tbl_contains(sourced.filetypes, filetype) then
          for _, item in pairs(sourced.snippets) do
            if item.filetype == filetype then
              coroutine.yield(item)
            end
          end
        end
      end
    end)
  end

  return loader
end

return M
