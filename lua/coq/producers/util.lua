local async = require "coq.lib.async"
local fuzzy = require "coq.lib.index.fuzzy"
local measure = require "coq.lib.index.rank.measure"
local producer = require "coq.lib.producers"
local trie = require "coq.lib.index.trie"

local M = {}

---@param ctx ctx.full
---@return boolean
M.skip_empty = function(ctx)
  return ctx.match_before == "" and not ctx.manual
end

---@param item { word: string }
---@return string
local word_key = function(item)
  return item.word
end

---@generic Ctx : { match_before?: string }
---@generic Item : { word: string }
---@param settings config.Settings
---@return fun(): index.Searcher<Ctx, Item>
M.word_search = function(settings)
  ---@param ctx { match_before?: string }
  ---@return string?
  local query_of = function(ctx)
    if ctx.match_before and ctx.match_before ~= "" then
      return ctx.match_before
    end
    return nil
  end

  return function()
    return trie.new {
      insert_key = word_key,
      query_key = query_of,
      prefix = settings.match.exact_matches,
      child = function()
        return fuzzy.new {
          cutoff = settings.match.fuzzy_cutoff,
          look_ahead = settings.match.look_ahead,
          insert_key = word_key,
          query_key = query_of,
        }
      end,
    }
  end
end

---@generic R
---@param fn fun(...): R
---@return fun(...): R
M.once = function(fn)
  local cached = nil
  return function(...)
    if cached == nil then
      cached = fn(...)
    end
    return cached
  end
end

---@param filetype string
---@param iter lib.Iterator<string>
---@return completions.ItemDoc?
M.doc = function(filetype, iter)
  local lines = vim.iter(iter):totable()
  if #lines == 0 then
    return nil
  end
  return { lines = lines, filetype = filetype }
end

---@return string
M.uid = function()
  local bytes = assert(vim.uv.random(8))
  return (string.gsub(bytes, ".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

---@class producers.ItemSpec
---@field word string
---@field abbr? string
---@field kind string
---@field filter string
---@field fuzzy number
---@field doc? completions.ItemDoc
---@field path? string
---@field lsp? completions.ItemLspMeta

---@param settings config.Settings
---@param source string
---@param spec producers.ItemSpec
---@return completions.Item
M.item = function(settings, source, spec)
  local opts = settings.clients[source]
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
      source = source,
      always_on_top = opts.always_on_top,
      doc = spec.doc,
      path = spec.path,
      lsp = spec.lsp,
    },
  }
end

---@generic T : fun()
---@param settings config.Settings
---@param ctx ctx.full
---@param iter T
---@param keep_exact? boolean
---@return T
M.shape = function(settings, ctx, iter, keep_exact)
  local shaped = vim.iter(iter)
  if not keep_exact then
    shaped = shaped:filter(function(hit)
      return hit.item.word ~= ctx.match_before
    end)
  end
  shaped = shaped:unique(function(hit)
    return hit.item.word
  end)
  return function()
    return shaped:next()
  end
end

---@param settings config.Settings
---@param ctx ctx.full
---@param batch completions.Item[]
---@return boolean
M.yield_measured = function(settings, ctx, batch)
  return not not coroutine.yield(measure.batch(settings, ctx, batch))
end

M.BATCH = 420
---@param fn fun(settings: config.Settings, ctx: ctx.full)
---@return fun(settings: config.Settings, ctx: ctx.full) batched
M.batched = function(fn)
  return function(settings, ctx)
    ---@diagnostic disable-next-line: unused-vararg
    local iter = async.wrap(function(...)
      fn(settings, ctx)
    end)

    local batch, more = {}, true
    while true do
      local item = iter(more)
      if item == nil then
        break
      end
      table.insert(batch, item)
      if #batch >= M.BATCH then
        more = M.yield_measured(settings, ctx, batch)
        if not more then
          iter(false)
          return
        end
        batch = {}
        async.sleep(0)
      end
    end
    M.yield_measured(settings, ctx, batch)
  end
end

---@param name string
---@return fun(): producers.Producer<ctx.full>
M.threaded_module = function(name)
  local path = "coq.producers." .. name
  local mk = function(method)
    local src = string.format("return function(...) return require(%q).%s(...) end", path, method)
    return assert(load(src))()
  end

  return function()
    return producer.threaded {
      source = name,
      idle = mk "idle",
      matcher = mk "matcher",
    }
  end
end

return M
