local T = require "coq.lib.test"
local inserted = require "coq.completions.inserted"

local splice = function(text, first, last, replacement)
  return string.sub(text, 1, first) .. replacement .. string.sub(text, last + 1)
end

local position = function(text, offset, encoding)
  local lines = vim.split(string.sub(text, 1, offset), "\n", { plain = true })
  return { line = #lines - 1, character = vim.str_utfindex(lines[#lines], encoding) }
end

local offset = function(text, pos, encoding)
  local lines = vim.split(text, "\n", { plain = true })
  local bytes = 0
  for row = 1, pos.line do
    bytes = bytes + #lines[row] + 1
  end
  return bytes + vim.str_byteindex(lines[pos.line + 1], encoding, pos.character, true)
end

T.describe({ "edit shift equivalence" }, function(test)
  for _, encoding in ipairs { "utf-8", "utf-16", "utf-32" } do
    test({ encoding, timeout = 5000 * T.SLOW }, function()
      local text = ""
      local boundaries = { 0 }
      for _, char in ipairs { "a", "\195\169", "\n", "\240\159\144\182", "b", "\n", "c" } do
        text = text .. char
        table.insert(boundaries, #text)
      end

      local checked = 0
      for _, first in ipairs(boundaries) do
        for _, last in ipairs(boundaries) do
          if first <= last then
            for _, replacement in ipairs { "", "z", "\195\169\240\159\144\182", "\nx\n" } do
              local completed = splice(text, first, last, replacement)
              local shift = {
                before = position(text, last, encoding),
                after = position(completed, first + #replacement, encoding),
              }
              for _, start in ipairs(boundaries) do
                for _, stop in ipairs(boundaries) do
                  local before = stop <= first and start < first
                  local after = start >= last and (last > first or stop > last)
                  if start <= stop and (before or after) then
                    local edits = {
                      {
                        range = { start = position(text, start, encoding), ["end"] = position(text, stop, encoding) },
                        newText = "Q\nR",
                      },
                    }
                    local original = vim.deepcopy(edits)
                    local shifted = inserted._shift_edits(edits, shift)
                    local edit = shifted[1]
                    local actual = splice(
                      completed,
                      offset(completed, edit.range.start, encoding),
                      offset(completed, edit.range["end"], encoding),
                      edit.newText
                    )
                    -- Right-to-left string splices use only original byte offsets.
                    local expected = before and splice(completed, start, stop, edit.newText)
                      or splice(splice(text, start, stop, edit.newText), first, last, replacement)
                    local case = { first, last, replacement, start, stop }
                    T.eq({ case = case, text = actual }, { case = case, text = expected })
                    T.eq(edits, original)
                    checked = checked + 1
                  end
                end
              end
            end
          end
        end
      end
      assert(checked > 1000, "insufficient edit combinations")
    end)
  end
end)
