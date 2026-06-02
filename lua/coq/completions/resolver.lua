local async = require "coq.lib.async"
local lsp_util = require "coq.producers.lsp.util"

---@class completions.Resolver
---@field reset fun()
---@field resolve fun(ctx: ctx.base, item: completions.Item, timeout_ms?: integer): completions.ItemLspMeta?

local promise = function()
  local done, vals, waiters = false, {}, {}
  return {
    resolve = function(...)
      if done then
        return
      end
      done, vals = true, { ... }
      local ws = waiters
      waiters = {}
      for _, w in ipairs(ws) do
        w.resolve(unpack(vals))
      end
    end,
    await = function()
      if done then
        return unpack(vals)
      end
      local w = async.future()
      table.insert(waiters, w)
      return w.await()
    end,
  }
end

---@param ctx ctx.base
---@param item completions.Item
---@return completions.ItemLspMeta?
local lsp_fetch = function(ctx, item)
  local lsp = item.meta.lsp
  if not lsp then
    return nil
  end
  return lsp_util.merge(lsp, lsp_util.resolve(ctx, lsp))
end

local M = {}

---@param n async.Nursery
---@param fetch? fun(ctx: ctx.base, item: completions.Item): completions.ItemLspMeta?
---@return completions.Resolver
M.new = function(n, fetch)
  fetch = fetch or lsp_fetch
  local cache, inflight = {}, {}

  local resolver = {}

  resolver.reset = function()
    cache, inflight = {}, {}
  end

  resolver.resolve = function(ctx, item, timeout_ms)
    local key = item.meta.uid
    local hit = cache[key]
    if hit then
      return hit[1]
    end

    local p = inflight[key]
    if not p then
      p = promise()
      inflight[key] = p
      n.spawn(function()
        local ok, v = pcall(fetch, ctx, item)
        local result = ok and v or item.meta.lsp
        cache[key] = { result }
        p.resolve(result)
      end)
    end
    if timeout_ms and timeout_ms > 0 then
      return async.wait(timeout_ms, p.await) or item.meta.lsp
    end
    return p.await()
  end

  ---@cast resolver completions.Resolver
  return resolver
end

return M
