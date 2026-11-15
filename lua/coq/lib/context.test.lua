local T = require "coq.lib.test"
local buffers = require "coq.lib.buffers"
local context = require "coq.lib.context"
local lib = require "coq.lib"

T.describe({ "context" }, function(test)
  test({ "full context captures locality once" }, function()
    lib.scope(function(defer)
      local original = buffers.lines_around_cursor
      defer(function()
        buffers.lines_around_cursor = original
      end)
      local calls = 0
      ---@diagnostic disable-next-line: duplicate-set-field
      buffers.lines_around_cursor = function()
        calls = calls + 1
        return { "dog dog", "rex" }
      end
      local full = context.full()
      T.eq(calls, 1)
      T.eq(full.locality, { dog = 2, rex = 1 })
      T.eq(full.buf, vim.api.nvim_get_current_buf())
    end)
  end)
end)
