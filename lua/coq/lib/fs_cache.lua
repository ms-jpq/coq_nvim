local atools = require "coq.lib.atools"
local json = require "coq.lib.json"

local M = {}

---@class fs_cache.Spec<V>
---@field fs_root string
---@field compute fun(key: string): V?

---@class fs_cache.Store<V>
---@field fetch fun(key: string, mtime: integer): V?
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

---@param path string
---@param data string
---@return uv.error_name?
local write_atomic = function(path, data)
  local m_err = atools.fs.mkdirp(vim.fs.dirname(path))
  if m_err then
    return m_err
  end
  local tmp = path .. ".tmp"
  local s_err = atools.fs.spit(tmp, data)
  if s_err then
    return s_err
  end
  return atools.fs.rename(tmp, path)
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
      local valid = mtime > 0 and cached_mtime and cached_mtime >= mtime

      if valid then
        local raw = atools.fs.slurp(path)
        if raw then
          local cached = json.decode(raw)
          if cached ~= nil then
            return cached
          end
        end
      end

      local value = spec.compute(key)
      if value == nil then
        return nil
      end
      local _ = write_atomic(path, json.encode(value, true))
      return value
    end,
    prune = function(key)
      atools.fs.unlink(path_of(key))
    end,
  }
end

return M
