local T = require "coq.lib.test"
local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

T.describe({ "atools.fs._drainable" }, function(test)
  local fs = atools.fs

  test({ "invoke dispatches and resolves with whatever the cb passes" }, function()
    local captured
    local fake = function(arg, cb)
      cb(nil, arg .. "!")
    end
    async.scope(function()
      local call, _ = fs._drainable(fake)
      captured = { call "spot" }
    end)
    T.eq(captured, { nil, "spot!" })
  end)

  test({ "drain is a noop when no call is pending" }, function()
    local called = false
    async.scope(function()
      local _, drain = fs._drainable(function() end)
      drain()
      called = true
    end)
    T.eq(called, true)
  end)

  test({ "drain waits non-cancellably for the pending callback" }, function()
    -- Simulate libuv: cb fires after a vim.schedule tick.
    local fake = function(cb)
      vim.schedule(function()
        cb "fido"
      end)
    end

    local drained_value
    async.scope(function(n)
      local call, drain = fs._drainable(fake)

      local h = n.spawn(function()
        -- this await will be cancelled before fake's vim.schedule fires
        call()
      end)

      -- Cancel the spawn before the cb has a chance to resolve, then drain.
      h.cancel()

      -- drain must wait for vim.schedule to flush, then for the cb to fire.
      drain()
      -- pending should now be nil; second drain is noop and doesn't error
      drained_value = "drained"
      drain()
    end)
    T.eq(drained_value, "drained")
  end)

  test({ "drain is non-cancellable: ignores outer handle cancellation" }, function()
    local fake = function(cb)
      vim.schedule(function()
        cb()
      end)
    end

    local survived = false
    async.scope(function(n)
      local call, drain = fs._drainable(fake)

      local h = n.spawn(function()
        call()
      end)
      h.cancel()

      -- Even though the parent scope's handle is being torn down, drain
      -- must complete (cancel = false on its inner await).
      drain()
      survived = true
    end)
    T.eq(survived, true)
  end)
end)

---@param contents string
---@return string path
local write_tmp = function(contents)
  local path = vim.fn.tempname()
  local f = assert(io.open(path, "w"))
  f:write(contents)
  f:close()
  return path
end

---@param iter fun(): string?
---@return string[]
local drain = function(iter)
  local out = {}
  for line in iter do
    table.insert(out, line)
  end
  return out
end

T.describe({ "atools.fs.scanfile" }, function(test)
  test({ "concatenated chunks reproduce file contents" }, function()
    local path = write_tmp "lil\nspot\nfido"
    local chunks
    async.scope(function()
      local close, iter = atools.fs.scanfile(path)
      chunks = drain(iter)
      close()
    end)

    T.eq(table.concat(chunks), "lil\nspot\nfido")
  end)

  test({ "empty file yields nothing" }, function()
    local path = write_tmp ""
    local chunks
    async.scope(function()
      local close, iter = atools.fs.scanfile(path)
      chunks = drain(iter)
      close()
    end)

    T.eq(chunks, {})
  end)

  test({ "missing file yields nothing" }, function()
    local path = vim.fn.tempname() .. "/does-not-exist"
    local chunks
    async.scope(function()
      local close, iter = atools.fs.scanfile(path)
      chunks = drain(iter)
      close()
    end)

    T.eq(chunks, {})
  end)
end)

T.describe({ "atools.fs.scandir" }, function(test)
  local mkdir = function(p)
    vim.fn.mkdir(p, "p")
  end

  local touch = function(p)
    assert(io.open(p, "w")):close()
  end

  local tmpdir = function()
    local p = vim.fn.tempname()
    mkdir(p)
    return p
  end

  test({ "yields each entry with name and kind" }, function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    mkdir(dir .. "/fido")

    local seen = {}
    async.scope(function()
      local close, iter = atools.fs.scandir(dir)
      for name, kind in iter do
        seen[name] = kind
      end
      close()
    end)

    T.eq(seen["spot.txt"], "file")
    T.eq(seen["fido"], "directory")
  end)

  test({ "missing path yields nothing" }, function()
    local count
    async.scope(function()
      count = 0
      local close, iter = atools.fs.scandir "/no/such/path/4242"
      for _ in iter do
        count = count + 1
      end
      close()
    end)
    T.eq(count, 0)
  end)

  test({ "iter exhausts naturally" }, function()
    local dir = tmpdir()
    for i = 1, 3 do
      touch(dir .. "/p" .. i .. ".txt")
    end

    local count = 0
    async.scope(function()
      local close, iter = atools.fs.scandir(dir)
      for _ in iter do
        count = count + 1
      end
      close()
    end)
    T.eq(count, 3)
  end)
end)
