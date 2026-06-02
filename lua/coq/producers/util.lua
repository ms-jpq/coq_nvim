local itertools = require "coq.lib.itertools"

local M = {}

---@generic A, R
---@param fn fun(arg: A): R
---@return fun(arg?: A): R
M.once = function(fn)
  local cached
  return function(arg)
    if cached == nil then
      cached = fn(arg)
    end
    return cached
  end
end

---@return string
M.uid = function()
  local bytes = assert(vim.uv.random(8))
  return (string.gsub(bytes, ".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

---@param item { word: string? }
---@return string?
local word_of = function(item)
  return item.word
end

---@generic T : { word: string? }
---@param settings config.Settings
---@param ctx ctx.full
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.shape = function(settings, ctx, iter)
  local kw = ctx.keyword_before
  local filtered = function()
    for v in iter do
      if v.word ~= kw then
        return v
      end
    end
    return nil
  end
  return itertools.take(settings.match.max_results, itertools.uniq_by(word_of, filtered))
end

return M
