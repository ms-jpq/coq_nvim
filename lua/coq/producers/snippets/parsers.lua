local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local txt = require "coq.lib.text"

---@param s string
---@return string
local strip = function(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param value string|string[]|nil
---@return string
local join_body = function(value)
  if type(value) == "string" then
    return value
  end
  if type(value) == "table" then
    return table.concat(value, "\n")
  end
  return ""
end

---@param prefix string|string[]|nil
---@param content string
---@return string[]
local prefix_set = function(prefix, content)
  if prefix == nil then
    return { content }
  end
  if type(prefix) == "string" then
    return { strip(prefix) }
  end
  if type(prefix) == "table" then
    return vim.iter(prefix):map(strip):totable()
  end
  return {}
end

local M = {}

---@param src snippets.Source
---@return lib.Iterator<snippets.Item>
M.bundle = function(src)
  return async.wrap(function()
    local body = atools.fs.slurp(src.path)
    if body == nil then
      return
    end
    local ok, json = pcall(vim.json.decode, body)
    if not ok or type(json) ~= "table" or type(json.snippets) ~= "table" then
      return
    end

    for _, snip in pairs(json.snippets) do
      if type(snip) == "table" and type(snip.filetype) == "string" then
        local matches = type(snip.matches) == "table" and snip.matches or {}
        local doc = type(snip.doc) == "string" and snip.doc ~= "" and snip.doc or nil
        local label = type(snip.label) == "string" and snip.label ~= "" and snip.label or nil
        for word in pairs(matches) do
          coroutine.yield {
            word = word,
            body = snip.content or "",
            filetype = snip.filetype,
            label = label,
            doc = doc,
          }
        end
      end
    end
  end)
end

---@param src snippets.Source
---@return lib.Iterator<snippets.Item>
M.lsp = function(src)
  return async.wrap(function()
    local body = atools.fs.slurp(src.path)
    if body == nil then
      return
    end
    local ok, json = pcall(vim.json.decode, body)
    if not ok or type(json) ~= "table" then
      return
    end

    local filetype = src.filetypes[1] or ""
    for label, unit in pairs(json) do
      if type(unit) == "table" then
        local content = strip(join_body(unit.body))
        local doc = strip(join_body(unit.description))

        for _, word in pairs(prefix_set(unit.prefix, content)) do
          coroutine.yield {
            word = word,
            body = content,
            filetype = filetype,
            label = label,
            doc = doc ~= "" and doc or nil,
          }
        end
      end
    end
  end)
end

---@param src snippets.Source
---@return lib.Iterator<snippets.Item>
M.neosnippet = function(src)
  return async.wrap(function()
    local body = atools.fs.slurp(src.path)
    if body == nil then
      return
    end
    local filetype = src.filetypes[1] or ""

    local name, label = "", ""
    local aliases, lines = {}, {}

    local flush = function()
      if name == "" then
        return
      end
      local content = strip(table.concat(lines, "\n"))
      local lbl = label ~= "" and label or nil
      for _, m in pairs(aliases) do
        coroutine.yield {
          word = m,
          body = content,
          filetype = filetype,
          label = lbl,
        }
      end
      name, label = "", ""
      aliases, lines = {}, {}
    end

    for line in txt.splitlines(body) do
      line = (line:gsub("%s+$", ""))
      if line == "" or line:match "^%s*$" then
        if name ~= "" then
          table.insert(lines, "")
        end
      elseif line:match "^#" then
        -- comment
      elseif line:match "^delete" or line:match "^options" or line:match "^regexp" or line:match "^source" then
        -- ignored directives
      elseif line:match "^extends" or line:match "^include" then
        -- filetype-extension; not modelled in v2 Source.filetypes yet
      elseif line:match "^snippet%s" then
        flush()
        local rest = strip(line:sub(#"snippet" + 1))
        local n, lbl = rest:match "^(%S+)%s*(.*)$"
        if lbl and lbl:sub(1, 1) == '"' and lbl:sub(-1) == '"' and #lbl >= 2 then
          lbl = lbl:sub(2, -2)
        end
        name = n or ""
        label = lbl or ""
        if name ~= "" then
          table.insert(aliases, name)
        end
      elseif line:match "^alias%s" then
        table.insert(aliases, strip(line:sub(#"alias" + 1)))
      elseif line:match "^abbr%s" then
        label = strip(line:sub(#"abbr" + 1))
      elseif line:match "^%s" then
        table.insert(lines, line)
      end
    end
    flush()
  end)
end

---@type table<snippets.Kind, fun(src: snippets.Source): lib.Iterator<snippets.Item>>
M.by_kind = {
  bundle = M.bundle,
  neosnippet = M.neosnippet,
  lsp = M.lsp,
}

return M
