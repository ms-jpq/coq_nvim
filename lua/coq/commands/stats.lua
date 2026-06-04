local float = require "coq.commands.float"
local txt = require "coq.lib.text"

local NS = "COQstats"

local M = {}

local H_SEP = " | "
local V_SEP = "─"

---@param sources string[]
---@param headers string[]
---@param row_of fun(source: string, header: string): string
---@return fun(): string?
local table_block = function(sources, headers, row_of)
  table.sort(sources)

  local col0_w = 0
  for _, s in pairs(sources) do
    col0_w = math.max(col0_w, #s)
  end
  local col_w = {}
  for _, h in pairs(headers) do
    col_w[h] = #h
    for _, s in pairs(sources) do
      col_w[h] = math.max(col_w[h], #row_of(s, h))
    end
  end

  return coroutine.wrap(function()
    local head = { txt.pad_right("", col0_w) }
    for _, h in pairs(headers) do
      table.insert(head, txt.pad_right(h, col_w[h]))
    end
    local header_line = table.concat(head, H_SEP)
    coroutine.yield(header_line)
    coroutine.yield(string.rep(V_SEP, #header_line))

    for _, s in pairs(sources) do
      local row = { txt.pad_right(s, col0_w) }
      for _, h in pairs(headers) do
        table.insert(row, txt.pad_right(row_of(s, h), col_w[h]))
      end
      coroutine.yield(table.concat(row, H_SEP))
    end
  end)
end

---@param n number
---@return string
local fmt_duration = function(n)
  if n < 1e-3 then
    return string.format("%dµs", math.floor(n * 1e6))
  end
  if n < 1 then
    return string.format("%dms", math.floor(n * 1e3))
  end
  return string.format("%.2fs", n)
end

---@param summary table<string, statsd.Summary>
---@return fun(): string?
local build = function(summary)
  return coroutine.wrap(function()
    coroutine.yield "# Statistics"
    coroutine.yield ""

    local sources = vim.tbl_keys(summary)
    if #sources == 0 then
      coroutine.yield "_No completions recorded yet._"
      return
    end

    local blocks = {
      table_block(sources, { "Interrupted", "Inserted" }, function(s, h)
        return tostring(h == "Interrupted" and summary[s].interrupted or summary[s].inserted)
      end),
      table_block(
        sources,
        { "Avg Duration", "Q10 Duration", "Q50 Duration", "Q95 Duration", "Q99 Duration" },
        function(s, h)
          local sum = summary[s]
          local field = ({
            ["Avg Duration"] = sum.avg_duration,
            ["Q10 Duration"] = sum.q10_duration,
            ["Q50 Duration"] = sum.q50_duration,
            ["Q95 Duration"] = sum.q95_duration,
            ["Q99 Duration"] = sum.q99_duration,
          })[h]
          return fmt_duration(field)
        end
      ),
      table_block(sources, { "Avg Items", "Q50 Items", "Q99 Items" }, function(s, h)
        local sum = summary[s]
        local field = ({
          ["Avg Items"] = sum.avg_items,
          ["Q50 Items"] = sum.q50_items,
          ["Q99 Items"] = sum.q99_items,
        })[h]
        return tostring(math.floor(field + 0.5))
      end),
    }

    for _, blk in pairs(blocks) do
      for ln in blk do
        coroutine.yield(ln)
      end
      coroutine.yield ""
    end
  end)
end

---@param statsd index.Statsd
M.show = function(statsd)
  float.show {
    ns = NS,
    lines = vim.iter(build(statsd.summary())):totable(),
    filetype = "markdown",
  }
end

return M
