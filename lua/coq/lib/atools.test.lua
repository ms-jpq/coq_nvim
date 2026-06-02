local T = require "coq.lib.test"
local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

T.describe("atools.spawn", function(test)
  test("captures stdout, stderr, and exit code", function()
    local result
    async.scope(function()
      result = atools.spawn { "sh", "-c", "printf fido; printf lil >&2; exit 7" }
    end)
    T.eq(result.code, 7)
    T.eq(result.signal, 0)
    T.eq(result.stdout, "fido")
    T.eq(result.stderr, "lil")
  end)

  test("writes stdin and the child reads it back", function()
    local result
    async.scope(function()
      result = atools.spawn({ "cat" }, { stdin = "fido\nlil\nspot" })
    end)
    T.eq(result.code, 0)
    T.eq(result.stdout, "fido\nlil\nspot")
  end)

  test("ambient cancel kills the child before it finishes naturally", function()
    local elapsed_ms
    async.scope(function(n)
      n.spawn(function()
        local start = vim.uv.hrtime()
        pcall(atools.spawn, { "sleep", "60" })
        elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      end)
      async.sleep(5 * T.SLOW)
      n.cancel()
    end)
    assert(elapsed_ms and elapsed_ms < 100 * T.SLOW, "expected fast kill, got " .. tostring(elapsed_ms) .. " ms")
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

T.describe("atools.fs.lines", function(test)
  test("yields each line of the file", function()
    local path = write_tmp "lil\nspot\nfido"
    local lines
    async.scope(function()
      lines = drain(atools.fs.lines(path))
    end)

    T.eq(lines, { "lil", "spot", "fido" })
  end)

  test("empty file yields a single empty string", function()
    local path = write_tmp ""
    local lines
    async.scope(function()
      lines = drain(atools.fs.lines(path))
    end)

    T.eq(lines, { "" })
  end)

  test("trailing newline yields an empty final line", function()
    local path = write_tmp "lil\nspot\n"
    local lines
    async.scope(function()
      lines = drain(atools.fs.lines(path))
    end)

    T.eq(lines, { "lil", "spot", "" })
  end)

  test("missing file returns a dead iterator", function()
    local path = vim.fn.tempname() .. "/does-not-exist"
    local lines
    async.scope(function()
      lines = drain(atools.fs.lines(path))
    end)

    T.eq(lines, {})
  end)
end)

T.describe("atools.fs.scandir", function(test)
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

  test("yields each entry with name and kind", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    mkdir(dir .. "/fido")

    local seen = {}
    async.scope(function()
      for name, kind in atools.fs.scandir(dir) do
        seen[name] = kind
      end
    end)

    T.eq(seen["spot.txt"], "file")
    T.eq(seen["fido"], "directory")
  end)

  test("missing path yields nothing", function()
    local count
    async.scope(function()
      count = 0
      for _ in atools.fs.scandir "/no/such/path/4242" do
        count = count + 1
      end
    end)
    T.eq(count, 0)
  end)

  test("iter exhausts naturally", function()
    local dir = tmpdir()
    for i = 1, 3 do
      touch(dir .. "/p" .. i .. ".txt")
    end

    local count = 0
    async.scope(function()
      for _ in atools.fs.scandir(dir) do
        count = count + 1
      end
    end)
    T.eq(count, 3)
  end)
end)
