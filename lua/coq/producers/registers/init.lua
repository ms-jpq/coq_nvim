local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local index_m = require "coq.producers.registers.index"
local set = require "coq.lib.set"
local tokens = require "coq.lib.index.tokens"
local txt = require "coq.lib.text"
local util = require "coq.producers.util"
local worker = require "coq.lib.worker"

---@type table<integer, true>
local BASIC_KW = (function()
  local kw = {}
  for b = string.byte "0", string.byte "9" do
    kw[b] = true
  end
  for b = string.byte "A", string.byte "Z" do
    kw[b] = true
  end
  for b = string.byte "a", string.byte "z" do
    kw[b] = true
  end
  kw[string.byte "_"] = true
  kw[string.byte "-"] = true
  return kw
end)()

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

---@param register string
---@param text string
---@return lib.Iterator<registers.Item>
local word_items = function(register, text)
  return async.wrap(function()
    for word in
      tokens.keywords(BASIC_KW, vim.iter { text } --[[@as lib.Iterator<string>]])
    do
      coroutine.yield {
        word = word,
        register = register,
        linewise = false,
      }
    end
  end)
end

---@param register string
---@param text string
---@return lib.Iterator<registers.Item>
local line_items = function(register, text)
  return async.wrap(function()
    for line in txt.splitlines(text) do
      local stripped = (string.gsub(line, "^%s+", ""))
      if stripped ~= "" then
        local head = tokens.keywords(BASIC_KW, vim.iter { stripped } --[[@as lib.Iterator<string>]])()
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
---@param _ idle.Ctx
M.idle = function(settings, _)
  local opts = settings.clients.registers
  local word_set = set.new(opts.words)
  local line_set = set.new(opts.lines)
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

  local by_register = {}
  for _, entry in pairs(fetched) do
    local text = entry.text
    if type(text) == "string" and text ~= "" then
      local bucket = {}
      by_register[entry.register] = bucket
      if word_set[entry.register] then
        for item in word_items(entry.register, text) do
          table.insert(bucket, item)
        end
      end
      if line_set[entry.register] then
        for item in line_items(entry.register, text) do
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

  local raw = index_of(settings).search { keyword_before = ctx.keyword_before }

  for hit in util.shape(settings, ctx, raw) do
    local doc_line = settings.clients.registers.short_name
      .. settings.clients.registers.register_scope
      .. hit.item.register

    local item = util.item(settings, settings.clients.registers, {
      word = hit.item.word,
      kind = "Text",
      filter = hit.item.word,
      fuzzy = hit.fuzzy,
      snippet = hit.item.linewise and hit.item.line or nil,
      doc = { lines = { doc_line }, filetype = "" },
    })
    coroutine.yield(item)
  end
end)

M.new = util.threaded_module "coq.producers.registers"

return M
