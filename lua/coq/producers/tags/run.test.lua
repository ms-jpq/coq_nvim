local T = require "coq.lib.test"
local async = require "coq.lib.async"
local parse = require "coq.producers.tags.parse"
local run = require "coq.producers.tags.run"

---@param contents string
---@param suffix string
---@return string
local write_tmp = function(contents, suffix)
  local path = vim.fn.tempname() .. suffix
  local f = assert(io.open(path, "w"))
  f:write(contents)
  f:close()
  return path
end

T.describe({ "tags.run :: end-to-end with real ctags" }, function(test)
  test({ "shells to ctags, parses tags from a python source" }, function()
    if vim.fn.executable "ctags" == 0 then
      return
    end

    local path = write_tmp(
      table.concat({
        "def fido():",
        "    return 1",
        "",
        "class Spot:",
        "    def bark(self):",
        "        return 2",
        "",
      }, "\n"),
      ".py"
    )

    local tags
    async.scope(function()
      local raw = run.run("ctags", { path })
      assert(raw, "ctags produced no output")
      tags = vim.iter(parse.parse(raw)):totable()
    end)

    local by_name = {}
    for _, t in pairs(tags) do
      by_name[t.word] = t
    end

    T.eq(by_name.fido.kind, "function")
    T.eq(by_name.fido.filename, path)
    T.eq(by_name.fido.filetype, "python")
    T.eq(by_name.fido.line, 1)

    T.eq(by_name.Spot.kind, "class")
    T.eq(by_name.Spot.line, 4)

    T.eq(by_name.bark.kind, "member")
    T.eq(by_name.bark.scope, "Spot")
    T.eq(by_name.bark.scopeKind, "class")
  end)

  test({ "empty path list yields nil without spawning" }, function()
    local raw
    async.scope(function()
      raw = run.run("ctags", {})
    end)
    T.eq(raw, nil)
  end)
end)
