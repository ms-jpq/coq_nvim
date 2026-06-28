local T = require "coq.lib.test"
local async = require "coq.lib.async"
local preview = require "coq.producers.paths.preview"

local mkdir = function(path)
  vim.fn.mkdir(path, "p")
end

local touch = function(path, content)
  local f = assert(io.open(path, "wb"))
  if content then
    f:write(content)
  end
  f:close()
end

---@return string
local tmpdir = function()
  local p = vim.fn.tempname()
  mkdir(p)
  return p
end

---@param opts paths.IterOpts
---@param cwd? string
---@param path string
---@return string[]
local collect = function(opts, cwd, path)
  local out
  async.scope(function()
    out = vim.iter(preview.lines(opts, cwd, path)):totable()
  end)
  return out or {}
end

T.describe({ "paths.preview.lines" }, function(test)
  test({ "nonexistent path yields a stat error line" }, function()
    local lines = collect({ max_lines = 10 }, nil, "/no/such/path/4242")
    T.eq(#lines, 1)
    assert(string.match(lines[1], "^%(stat: "), "expected stat-error line, got: " .. lines[1])
  end)

  test({ "directory yields sorted entries with / on subdirs" }, function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    mkdir(dir .. "/fido")
    touch(dir .. "/airedale.md")

    T.eq(collect({ max_lines = 10 }, nil, dir), { "airedale.md", "fido/", "spot.txt" })
  end)

  test({ "directory renders via fmt_path when cwd is given" }, function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    mkdir(dir .. "/fido")

    T.eq(collect({ max_lines = 10 }, dir, dir), { "./fido/", "./spot.txt" })
  end)

  test({ "directory emits ellipsis after max_lines entries on truncation" }, function()
    local dir = tmpdir()
    for i = 1, 5 do
      touch(dir .. "/p" .. i .. ".txt")
    end

    local lines = collect({ max_lines = 3, ellipsis = "…" }, nil, dir)
    T.eq(lines, { "p1.txt", "p2.txt", "p3.txt", "…" })
  end)

  test({ "directory at exact max_lines emits all entries, no ellipsis" }, function()
    local dir = tmpdir()
    for i = 1, 3 do
      touch(dir .. "/p" .. i .. ".txt")
    end

    local lines = collect({ max_lines = 3, ellipsis = "…" }, nil, dir)
    T.eq(lines, { "p1.txt", "p2.txt", "p3.txt" })
  end)

  test({ "file yields rstripped lines" }, function()
    local dir = tmpdir()
    local path = dir .. "/dogs.txt"
    touch(path, "labrador  \nlily\t\nspot")

    T.eq(collect({ max_lines = 10 }, nil, path), { "labrador", "lily", "spot" })
  end)

  test({ "file emits ellipsis on truncation" }, function()
    local dir = tmpdir()
    local path = dir .. "/dogs.txt"
    touch(path, "labrador\nlily\nspot\nfido\nrex")

    local lines = collect({ max_lines = 3, ellipsis = "…" }, nil, path)
    T.eq(lines, { "labrador", "lily", "spot", "…" })
  end)

  test({ "empty file yields (empty) marker" }, function()
    local dir = tmpdir()
    local path = dir .. "/empty.txt"
    touch(path, "")

    T.eq(collect({ max_lines = 10 }, nil, path), { "(empty)" })
  end)

  test({ "binary file yields (binary) marker" }, function()
    local dir = tmpdir()
    local path = dir .. "/blob.bin"
    touch(path, "labrador\0\1\2\3spot")

    T.eq(collect({ max_lines = 10 }, nil, path), { "(binary)" })
  end)
end)
