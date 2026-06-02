local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local index_m = require "coq.producers.registers.index"
local producer = require "coq.lib.producers"
local tokens = require "coq.lib.index.tokens"
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

local index = util.once(index_m.new)

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

---@param settings config.Settings
---@param _ idle.Ctx
M.idle = function(settings, _)
  local opts = settings.clients.registers
  local words, lines = opts.words, opts.lines

  local fetch = function(name)
    return function()
      return {
        register = name,
        text = worker.main(function(...)
          return require("coq.producers.registers").getreg(...)
        end, name),
      }
    end
  end

  local jobs = {}
  for _, name in pairs(words) do
    table.insert(jobs, fetch(name))
  end
  for _, name in pairs(lines) do
    table.insert(jobs, fetch(name))
  end

  if #jobs == 0 then
    return
  end

  local fetched = async.all(jobs)

  local word_set = {}
  for _, name in pairs(words) do
    word_set[name] = true
  end
  local line_set = {}
  for _, name in pairs(lines) do
    line_set[name] = true
  end

  index(settings).prune {}

  for _, entry in pairs(fetched) do
    async.sleep(0)
    local text = entry.text
    if type(text) == "string" and text ~= "" then
      if word_set[entry.register] then
        for word in tokens.words(BASIC_KW, vim.gsplit(text, "\n", { plain = true })) do
          index(settings).insert {
            word = word,
            register = entry.register,
            linewise = false,
          }
        end
      end
      if line_set[entry.register] then
        for line in vim.gsplit(text, "\n", { plain = true }) do
          local stripped = (string.gsub(line, "^%s+", ""))
          if stripped ~= "" then
            local head = tokens.words(BASIC_KW, vim.iter { stripped } --[[@as lib.Iterator<string>]])()
            if head ~= nil then
              index(settings).insert {
                word = head,
                register = entry.register,
                linewise = true,
                line = stripped,
              }
            end
          end
        end
      end
    end
  end
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.registers
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]

  local raw = index(settings).search { keyword_before = ctx.keyword_before }
  local shaped = util.shape(settings, raw)

  for item in
    shaped --[[@as lib.Iterator<registers.Item>]]
  do
    if item.word ~= ctx.cword then
      local doc_line = opts.short_name .. opts.register_scope .. item.register
      coroutine.yield {
        word = item.word,
        kind = "Text",
        menu = menu,
        meta = {
          filter = item.word,
          source = opts.short_name,
          always_on_top = opts.always_on_top,
          snippet = item.linewise and item.line or nil,
          doc = { lines = { doc_line }, filetype = "" },
        },
      }
    end
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return producer.threaded {
    settings = settings,
    idle = function(...)
      require("coq.producers.registers").idle(...)
    end,
    matcher = function(...)
      require("coq.producers.registers").matcher(...)
    end,
  }
end

return M
