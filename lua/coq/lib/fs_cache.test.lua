local T = require "coq.lib.test"
local async = require "coq.lib.async"
local fs_cache = require "coq.lib.fs_cache"

---@return string
local tmpdir = function()
  local p = vim.fn.tempname()
  vim.fn.mkdir(p, "p")
  return p
end

---@param dir string
---@param name string
---@param data string
---@return string
local write = function(dir, name, data)
  local path = vim.fs.joinpath(dir, name)
  local f = assert(io.open(path, "w"))
  f:write(data)
  f:close()
  return path
end

T.describe({ "fs_cache.mtime_ns" }, function(test)
  test({ "returns ns mtime for an existing file" }, function()
    local dir = tmpdir()
    local path = write(dir, "labrador", "fido")
    local got
    async.scope(function()
      got = fs_cache.mtime_ns(path)
    end)
    T.eq(type(got), "number")
    assert(got > 0)
  end)

  test({ "returns nil for a missing file" }, function()
    local path = vim.fn.tempname() .. "/nope"
    local got
    async.scope(function()
      got = fs_cache.mtime_ns(path)
    end)
    T.eq(got, nil)
  end)
end)

T.describe({ "fs_cache.new" }, function(test)
  test({ "first fetch invokes compute and caches the result" }, function()
    local computes = 0
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function(key)
        computes = computes + 1
        return { key = key, payload = "labrador" }
      end,
    }

    ---@type { key: string, payload: string }?
    local result
    async.scope(function()
      result = store.fetch("dogs", 0)
    end)

    T.eq(computes, 1)
    T.eq(result and result.key, "dogs")
    T.eq(result and result.payload, "labrador")
  end)

  test({ "second fetch with stale mtime hits the cache" }, function()
    local computes = 0
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function()
        computes = computes + 1
        return { payload = "fido" }
      end,
    }

    local r1, r2
    async.scope(function()
      r1 = store.fetch("dogs", 0)
      r2 = store.fetch("dogs", 0)
    end)

    T.eq(computes, 1)
    T.eq(r1, r2)
  end)

  test({ "fetch with newer mtime recomputes" }, function()
    local computes = 0
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function()
        computes = computes + 1
        return { n = computes }
      end,
    }

    local r1, r2
    async.scope(function()
      r1 = store.fetch("dogs", 0)
      r2 = store.fetch("dogs", 2 ^ 62)
    end)

    T.eq(computes, 2)
    T.eq(r1.n, 1)
    T.eq(r2.n, 2)
  end)

  test({ "distinct keys do not collide on disk" }, function()
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function(key)
        return { who = key }
      end,
    }

    local a, b
    async.scope(function()
      a = store.fetch("fido", 0)
      b = store.fetch("spot", 0)
    end)

    T.eq(a.who, "fido")
    T.eq(b.who, "spot")
  end)

  test({ "keys with path-unsafe characters round-trip" }, function()
    local computes = 0
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function()
        computes = computes + 1
        return { payload = "lil" }
      end,
    }

    local r1, r2
    async.scope(function()
      r1 = store.fetch("/home/dogs/lil.txt", 0)
      r2 = store.fetch("/home/dogs/lil.txt", 0)
    end)

    T.eq(computes, 1)
    T.eq(r1, r2)
  end)

  test({ "prune removes the cache file, next fetch recomputes" }, function()
    local computes = 0
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function()
        computes = computes + 1
        return { n = computes }
      end,
    }

    async.scope(function()
      store.fetch("dogs", 0)
      store.prune "dogs"
      store.fetch("dogs", 0)
    end)

    T.eq(computes, 2)
  end)

  test({ "prune on a missing key is a no-op" }, function()
    local store = fs_cache.new {
      fs_root = tmpdir(),
      compute = function()
        return {}
      end,
    }

    async.scope(function()
      store.prune "no-such-dog"
    end)
  end)
end)
