local fuzzy = require "coq.lib.index.fuzzy"
local trie = require "coq.lib.index.trie"

local M = {}

---@param item { word: string }
---@return string
local word_key = function(item)
  return item.word
end

---@generic Ctx : { keyword_before?: string }
---@generic Item : { word: string }
---@param settings config.Settings
---@return fun(): index.Searcher<Ctx, Item>
M.word_search = function(settings)
  local prefix = settings.match.exact_matches
  return function()
    return trie.new {
      insert_key = word_key,
      query_key = function(ctx)
        return (ctx.keyword_before == nil or ctx.keyword_before == "") and nil or ctx.keyword_before
      end,
      prefix = prefix,
      child = function()
        return fuzzy.new { insert_key = word_key }
      end,
    }
  end
end

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

---@param hit index.Hit<any>
---@return string?
local word_of = function(hit)
  return hit.item.word
end

---@generic T : fun() index.Hit<any>
---@param settings config.Settings
---@param ctx ctx.full
---@param iter T
---@return T
M.shape = function(settings, ctx, iter)
  local kw = ctx.keyword_before
  local shaped = vim
    .iter(iter)
    :filter(function(hit)
      return hit.item.word ~= kw
    end)
    :unique(word_of)
    :take(settings.match.max_results)
  return function()
    return shaped:next()
  end
end

---@class producers.ItemSpec
---@field word string
---@field abbr? string
---@field kind string
---@field filter string
---@field fuzzy number
---@field doc? completions.ItemDoc
---@field snippet? string
---@field path? string
---@field lsp? completions.ItemLspMeta

---@param settings config.Settings
---@param opts { short_name: string, always_on_top: boolean? }
---@param spec producers.ItemSpec
---@return completions.Item
M.item = function(settings, opts, spec)
  local lhs, rhs = unpack(settings.display.pum.source_context)
  return {
    word = spec.word,
    abbr = spec.abbr,
    kind = spec.kind,
    menu = lhs .. opts.short_name .. rhs,
    meta = {
      uid = M.uid(),
      filter = spec.filter,
      fuzzy = spec.fuzzy,
      source = opts.short_name,
      always_on_top = opts.always_on_top,
      doc = spec.doc,
      snippet = spec.snippet,
      path = spec.path,
      lsp = spec.lsp,
    },
  }
end

return M
