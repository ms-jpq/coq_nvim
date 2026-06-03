local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"
local lsp_util = require "coq.producers.lsp.util"

---@class completions.Resolver
---@field reset fun()
---@field resolve fun(ctx: ctx.base, item: completions.Item, timeout_ms?: integer): completions.ItemLspMeta?

---@param ctx ctx.base
---@param item completions.Item
---@return completions.ItemLspMeta?
local lsp_fetch = function(ctx, item)
  local lsp = item.meta.lsp
  if not lsp then
    return nil
  end

  local resolved = lsp_util.resolve(ctx, lsp)
  return lsp_util.merge(lsp, resolved)
end

local M = {}

---@param n async.Nursery
---@param fetch? fun(ctx: ctx.base, item: completions.Item): completions.ItemLspMeta?
---@return completions.Resolver
M.new = function(n, fetch)
  fetch = fetch or lsp_fetch

  ---@return fun(ctx: ctx.base, item: completions.Item, timeout_ms?: integer): completions.ItemLspMeta?
  local instance = function()
    local cache = {}
    return function(ctx, item, timeout_ms)
      local key = item.meta.uid
      local f = cache[key]

      if not f then
        f = async.future()
        cache[key] = f

        n.spawn(function()
          local ok, v = pcall(fetch, ctx, item)
          if not ok then
            cache[key] = nil
            if not cancel.is(v) then
              errs.report(v)
            end
          end
          f.resolve(ok and v or item.meta.lsp)
        end)
      end

      if timeout_ms and timeout_ms > 0 then
        return async.wait(timeout_ms, f.await) or item.meta.lsp
      end
      return f.await()
    end
  end

  local impl = instance()

  local resolver = {}

  resolver.reset = function()
    impl = instance()
  end

  resolver.resolve = function(ctx, item, timeout_ms)
    return impl(ctx, item, timeout_ms)
  end

  ---@cast resolver completions.Resolver
  return resolver
end

return M
