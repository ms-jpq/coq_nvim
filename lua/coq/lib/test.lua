local async = require "coq.lib.async"
local tbl = require "coq.lib.tbl"

local registry = {}

local function register(prefix, spec, fn)
  if type(spec) == "string" then
    spec = { spec }
  end
  local name = prefix and (prefix .. " :: " .. spec[1]) or spec[1]
  table.insert(registry, { name = name, timeout = spec.timeout or 5000, fn = fn })
end

return {
  describe = function(prefix, body)
    body(function(spec, fn)
      register(prefix, spec, fn)
    end)
  end,
  test = function(spec, fn)
    register(nil, spec, fn)
  end,
  eq = function(a, b)
    if not vim.deep_equal(a, b) then
      error(("eq failed:\n  lhs = %s\n  rhs = %s"):format(vim.inspect(a), vim.inspect(b)), 2)
    end
  end,
  run = function(seed)
    seed = seed or vim.uv.hrtime()
    vim.notify("🎲 seed " .. seed, vim.log.levels.INFO)
    math.randomseed(seed)
    tbl.shuffle(registry)

    local start = vim.uv.hrtime()
    local max_timeout = 0

    for _, t in pairs(registry) do
      t.done = false
      t.err = nil
      t.timed_out = false
      max_timeout = math.max(max_timeout, t.timeout)

      async.run(function()
        local ok, e = xpcall(t.fn, debug.traceback)
        t.done = true
        if not ok then
          t.err = e
        end
      end)
    end

    vim.wait(max_timeout + 100, function()
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      local all_done = true
      for _, t in pairs(registry) do
        if not t.done then
          if elapsed_ms > t.timeout then
            t.timed_out = true
          else
            all_done = false
          end
        end
      end
      return all_done
    end)

    local failed = 0
    for _, t in ipairs(registry) do
      if t.timed_out then
        vim.notify("✗ " .. t.name .. "\n  timeout", vim.log.levels.ERROR)
        failed = failed + 1
      elseif t.err then
        vim.notify("✗ " .. t.name .. "\n" .. t.err, vim.log.levels.ERROR)
        failed = failed + 1
      else
        vim.notify("✓ " .. t.name, vim.log.levels.INFO)
      end
    end

    if failed > 0 then
      vim.notify(("%d failed"):format(failed), vim.log.levels.ERROR)
      os.exit(1)
    end
  end,
}
