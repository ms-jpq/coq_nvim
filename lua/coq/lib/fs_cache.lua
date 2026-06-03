local atools = require "coq.lib.atools"
local lib = require "coq.lib"

local M = {}

---@class fs_cache.Spec<V>
---@field fs_root string
---@field compute fun(key: string): V

---@class fs_cache.Store<V>
---@field fetch fun(key: string, mtime: integer): V
---@field prune fun(key: string)

---@param path string
---@return integer?
M.mtime_ns = function(path)
  local err, st = atools.fs.stat(path)
  if err or not st then
    return nil
  end
  return st.mtime.sec * 1000000000 + st.mtime.nsec
end

---@param key string
---@return string
local safe_name = function(key)
  return (string.gsub(key, "[^%w._-]", function(c)
    return string.format("%%%02x", string.byte(c))
  end))
end

---@param value any
---@return string
local encode = function(value)
  return vim.json.encode(value, { sort_keys = true, indent = [[  ]] })
end

---@param s string
---@return any
M.decode = function(s)
  local ok, value = pcall(function()
    return vim.json.decode(s, { luanil = { object = true, array = true } })
  end)
  if not ok then
    return nil
  end
  return value
end

---@param path string
---@return string?
local read_all = function(path)
  return lib.scope(function(defer)
    local close, iter = atools.fs.scanfile(path)
    defer(close)
    local chunks = vim.iter(iter):totable()
    return #chunks > 0 and table.concat(chunks) or nil
  end)
end

---@param path string
---@param data string
---@return boolean
local write_atomic = function(path, data)
  if atools.fs.mkdirp(vim.fs.dirname(path)) then
    return false
  end
  local tmp = path .. ".tmp"
  if atools.fs.writefile(tmp, data) then
    return false
  end
  return atools.fs.rename(tmp, path) == nil
end

---@generic V
---@param spec fs_cache.Spec<V>
---@return fs_cache.Store<V>
M.new = function(spec)
  local path_of = function(key)
    return vim.fs.joinpath(spec.fs_root, safe_name(key) .. ".json")
  end

  return {
    fetch = function(key, mtime)
      local path = path_of(key)
      local cached_mtime = M.mtime_ns(path)
      local valid = cached_mtime and cached_mtime >= mtime

      if valid then
        local raw = read_all(path)
        if raw then
          local cached = M.decode(raw)
          if cached ~= nil then
            return cached
          end
        end
      end

      local value = spec.compute(key)
      write_atomic(path, encode(value))
      return value
    end,
    prune = function(key)
      atools.fs.unlink(path_of(key))
    end,
  }
end

return M
