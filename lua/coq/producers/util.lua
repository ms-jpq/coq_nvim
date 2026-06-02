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

---@param settings config.Settings
---@param opts { short_name: string }
---@return string
M.menu = function(settings, opts)
  local lhs, rhs = unpack(settings.display.pum.source_context)
  return lhs .. opts.short_name .. rhs
end

---@class producers.ItemSpec
---@field word string
---@field abbr? string
---@field kind string
---@field menu string
---@field filter? string
---@field doc? completions.ItemDoc
---@field snippet? string

---@param opts { short_name: string, always_on_top: boolean? }
---@param spec producers.ItemSpec
---@return completions.Item
M.item = function(opts, spec)
  return {
    word = spec.word,
    abbr = spec.abbr,
    kind = spec.kind,
    menu = spec.menu,
    meta = {
      uid = M.uid(),
      filter = spec.filter,
      source = opts.short_name,
      always_on_top = opts.always_on_top,
      doc = spec.doc,
      snippet = spec.snippet,
    },
  }
end

return M
