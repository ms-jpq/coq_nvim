local async = require "coq.lib.async"
local tbl = require "coq.lib.tbl"

---@class lib.TestSpecTable
---@field [1] string
---@field timeout? integer
---@field only? boolean

---@alias lib.TestSpec string | lib.TestSpecTable

---@class lib.TestEntry
---@field name string
---@field timeout integer
---@field only boolean
---@field fn fun()
---@field done? boolean
---@field err? string
---@field timed_out? boolean
---@field elapsed_ms? number

local M = {}

local DEFAULT_TIMEOUT = tonumber(os.getenv "TEST_TIMEOUT") or 1000
local TOP_N = tonumber(os.getenv "TEST_TOP_N") or 10
local VERBOSE = os.getenv "TEST_VERBOSE" ~= nil

local registry = {}

---@param spec lib.TestSpec
---@return lib.TestSpecTable
local normalize = function(spec)
  if type(spec) == "string" then
    spec = { spec }
  end
  return spec
end

---@param prefix? string
---@param spec lib.TestSpec
---@param fn fun()
---@param group? lib.TestSpecTable
local register = function(prefix, spec, fn, group)
  spec = normalize(spec)
  ---@cast spec -string
  group = group or {}
  local name = prefix and (prefix .. " :: " .. spec[1]) or spec[1]

  table.insert(registry, {
    name = name,
    timeout = spec.timeout or group.timeout or DEFAULT_TIMEOUT,
    only = spec.only or group.only or false,
    fn = fn,
  })
end

---@param spec lib.TestSpec
---@param body fun(test: fun(spec: lib.TestSpec, fn: fun()))
M.describe = function(spec, body)
  spec = normalize(spec)
  ---@cast spec -string
  body(function(test_spec, fn)
    register(spec[1], test_spec, fn, spec)
  end)
end

---@param spec lib.TestSpec
---@param fn fun()
M.test = function(spec, fn)
  register(nil, spec, fn)
end

M.eq = function(a, b)
  if not vim.deep_equal(a, b) then
    error(("eq failed:\n  lhs = %s\n  rhs = %s"):format(vim.inspect(a), vim.inspect(b)), 2)
  end
end

---@param seed? integer
M.run = function(seed)
  do
    seed = seed or vim.uv.hrtime()
    vim.notify(("🎲 seed %.0f"):format(seed))
    math.randomseed(seed)
  end

  do
    local kept = vim
      .iter(registry)
      :filter(function(t)
        return t.only
      end)
      :totable()

    if #kept > 0 then
      registry = kept
      vim.notify(("⚑ only mode: %d tests"):format(#registry))
    end

    tbl.shuffle(registry)
  end

  do
    local start = vim.uv.hrtime()
    local max_timeout = 0

    for _, t in pairs(registry) do
      t.done = false
      t.err = nil
      t.timed_out = false
      t.elapsed_ms = 0
      max_timeout = math.max(max_timeout, t.timeout)

      async.entry(function()
        local t_start = vim.uv.hrtime()
        local ok, e = xpcall(t.fn, debug.traceback)
        t.elapsed_ms = (vim.uv.hrtime() - t_start) / 1e6
        t.done = true
        if not ok then
          t.err = e
        end
      end)()
    end

    vim.wait(max_timeout + 100, function()
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      local all_done = true
      for _, t in pairs(registry) do
        if not t.done then
          if elapsed_ms > t.timeout then
            t.timed_out = true
            t.elapsed_ms = t.timeout
          else
            all_done = false
          end
        end
      end
      return all_done
    end)
  end

  do
    local failed, passed = 0, 0
    for _, t in pairs(registry) do
      if t.timed_out then
        vim.notify("✗ " .. t.name .. "\n  timeout", vim.log.levels.ERROR)
        failed = failed + 1
      elseif t.err then
        vim.notify("✗ " .. t.name .. "\n" .. t.err, vim.log.levels.ERROR)
        failed = failed + 1
      else
        passed = passed + 1
        if VERBOSE then
          vim.notify("✓ " .. t.name)
        end
      end
    end
    if not VERBOSE then
      vim.notify(("✓ %d passed"):format(passed))
    end

    table.sort(registry, function(a, b)
      return a.elapsed_ms > b.elapsed_ms
    end)
    local n = math.min(#registry, TOP_N)
    vim.notify(("── slowest %d/%d tests ──"):format(n, #registry))

    vim.iter(registry):take(n):each(function(t)
      vim.notify(("%7.1f ms  %s"):format(t.elapsed_ms, t.name))
    end)

    if failed > 0 then
      vim.notify(("%d failed"):format(failed), vim.log.levels.ERROR)
      os.exit(1)
    end
  end
end

return M
