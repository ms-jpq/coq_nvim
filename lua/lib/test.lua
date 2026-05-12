local async = require "lib.async"

local registry = {}

return {
  test = function(spec, fn)
    if type(spec) == "string" then
      spec = { spec }
    end
    table.insert(registry, { name = spec[1], timeout = spec.timeout or 5000, fn = fn })
  end,
  eq = function(a, b)
    if not vim.deep_equal(a, b) then
      error(("eq failed:\n  lhs = %s\n  rhs = %s"):format(vim.inspect(a), vim.inspect(b)), 2)
    end
  end,
  run = function()
    local failed = 0
    for _, t in ipairs(registry) do
      local done = false
      local err = nil

      async.run(function()
        local ok, e = xpcall(t.fn, debug.traceback)
        done = true
        if not ok then
          err = e
        end
      end)

      vim.wait(t.timeout, function()
        return done
      end)

      if not done then
        vim.notify("   ✗ " .. t.name .. "\n  timeout", vim.log.levels.ERROR)
        failed = failed + 1
      elseif err then
        vim.notify("   ✗ " .. t.name .. "\n" .. err, vim.log.levels.ERROR)
        failed = failed + 1
      else
        vim.notify("   ✓ " .. t.name, vim.log.levels.INFO)
      end
    end

    if failed > 0 then
      vim.notify(("%d failed"):format(failed), vim.log.levels.ERROR)
      os.exit(1)
    end
  end,
}
