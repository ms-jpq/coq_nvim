local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local closable = require "coq.lib.closable"
local errs = require "coq.lib.errs"
local lib = require "coq.lib"
local lsp_util = require "coq.producers.lsp.util"

---@class completions.Resolver
---@field reset fun()
---@field resolve fun(ctx: ctx.base, meta: completions.ItemMeta, timeout_ms?: integer): completions.ItemLspMeta?

---@param ctx ctx.base
---@param meta completions.ItemMeta
---@return completions.ItemLspMeta?
local lsp_fetch = function(ctx, meta)
  local lsp = meta.lsp
  if not lsp then
    return nil
  end

  local resolved = lsp_util.resolve(ctx, lsp)
  return lsp_util.merge(lsp, resolved)
end

---@class resolver.Instance: lib.ClosableState
---@field resolve fun(ctx: ctx.base, meta: completions.ItemMeta, timeout_ms?: integer): completions.ItemLspMeta?

---@param n async.Nursery
---@param timelord completions.TimeLord
---@param fetch fun(ctx: ctx.base, meta: completions.ItemMeta): completions.ItemLspMeta?
---@return resolver.Instance
local new = function(n, timelord, fetch)
  local cache = {}
  local handles = lib.weak({}, "v")

  local state = closable.new(function()
    for _, h in pairs(handles) do
      h.cancel()
    end
  end)

  local resolve = function(ctx, meta, timeout_ms)
    local key = meta.uid
    local f = cache[key]

    if not f then
      f = async.future()
      cache[key] = f

      local h = n.spawn(function()
        local ok, v = pcall(fetch, ctx, meta)
        f.resolve(ok and v or nil)
        if not ok then
          cache[key] = nil
          if not cancel.is(v) then
            errs.report(v)
          end
        end
      end)
      table.insert(handles, h)
    end

    if timeout_ms and timeout_ms > 0 then
      return timelord.guard("resolve:" .. (meta.lsp and meta.lsp.client_name or ""), timeout_ms, f.await)
    end
    return f.await()
  end

  ---@diagnostic disable-next-line: missing-fields
  local instance = {} ---@type resolver.Instance
  instance.resolve = resolve

  setmetatable(instance, { __index = state })
  return instance
end

local M = {}

---@param n async.Nursery
---@param timelord completions.TimeLord
---@param fetch? fun(ctx: ctx.base, meta: completions.ItemMeta): completions.ItemLspMeta?
---@return completions.Resolver
M.new = function(n, timelord, fetch)
  fetch = fetch or lsp_fetch

  local instance = new(n, timelord, fetch)

  ---@diagnostic disable-next-line: missing-fields
  local resolver = {} ---@type completions.Resolver

  resolver.reset = function()
    instance.close()
    instance = new(n, timelord, fetch)
  end

  resolver.resolve = function(ctx, meta, timeout_ms)
    return instance.resolve(ctx, meta, timeout_ms)
  end

  return resolver
end

return M
