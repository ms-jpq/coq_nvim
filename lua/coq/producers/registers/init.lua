local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local index_m = require "coq.producers.registers.index"
local set = require "coq.lib.set"
local tokens = require "coq.lib.index.tokens"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

local SOURCE = "registers"

local index_of = util.once(index_m.new)

local M = {}

---@param name string
---@return string?
M.getreg = function(name)
  atools.scheduled()
  local ok, text = pcall(vim.fn.getreg, name)
  if not ok then
    return nil
  end
  if type(text) ~= "string" then
    return nil
  end
  return text
end

---@param iskeyword table<integer, integer>
---@param register string
---@param text string
---@return lib.Iterator<registers.Item>
local word_items = function(iskeyword, register, text)
  return async.wrap(function()
    for word in
      tokens.keywords(iskeyword, vim.iter { text } --[[@as lib.Iterator<string>]])
    do
      coroutine.yield {
        word = word,
        register = register,
        linewise = false,
      }
    end
  end)
end

---@param iskeyword table<integer, integer>
---@param register string
---@param text string
---@return lib.Iterator<registers.Item>
local line_items = function(iskeyword, register, text)
  return async.wrap(function()
    for line in txt.splitlines(text) do
      local stripped = txt.lstrip(line)
      if stripped ~= "" then
        local head = tokens.keywords(iskeyword, vim.iter { stripped } --[[@as lib.Iterator<string>]])()
        if head ~= nil then
          coroutine.yield {
            word = head,
            register = register,
            linewise = true,
            line = stripped,
          }
        end
      end
    end
  end)
end

---@param settings config.Settings
---@param idle_ctx idle.Ctx
M.idle = function(settings, idle_ctx)
  local word_set = set.new(settings.clients.registers.words)
  local line_set = set.new(settings.clients.registers.lines)
  local names = vim.tbl_keys(vim.tbl_extend("force", word_set, line_set))

  if #names == 0 then
    return
  end

  local fetched = async.all(vim.tbl_map(function(name)
    return function()
      return {
        register = name,
        text = worker.main(function(...)
          return require("coq.producers.registers").getreg(...)
        end, name),
      }
    end
  end, names))

  local iskeyword = tokens.parse_charset(idle_ctx.ctx.iskeyword)
  local by_register = {}
  for _, entry in pairs(fetched) do
    local text = entry.text
    if type(text) == "string" and text ~= "" then
      local bucket = {}
      by_register[entry.register] = bucket
      if word_set[entry.register] then
        for item in word_items(iskeyword, entry.register, text) do
          table.insert(bucket, item)
        end
      end
      if line_set[entry.register] then
        for item in line_items(iskeyword, entry.register, text) do
          table.insert(bucket, item)
        end
      end
    end
  end

  for _, name in pairs(names) do
    async.sleep(0)
    index_of(settings).prune { register = name }
    for _, item in pairs(by_register[name] or {}) do
      index_of(settings).insert(item)
    end
  end
end

---@param settings config.Settings
M.matcher = util.batched(function(settings, ctx)
  if util.skip_empty(ctx) then
    return
  end

  local raw = index_of(settings).search { match_before = ctx.match_before }

  for hit in util.shape(settings, ctx, raw) do
    local doc_line = settings.clients.registers.short_name
      .. settings.clients.registers.register_scope
      .. hit.item.register

    local item = util.item(settings, SOURCE, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      snippet = hit.item.linewise and hit.item.line or nil,
      doc = { lines = { doc_line }, filetype = "" },
    })
    if not coroutine.yield(item) then
      return
    end
  end
end)

M.new = util.threaded_module(SOURCE)

return M
