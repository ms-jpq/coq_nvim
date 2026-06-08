#!/usr/bin/env -S -- nvim -l

local repo_root = vim.fs.dirname(vim.fs.dirname(vim.uv.fs_realpath(arg[0])))
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local async = require "coq.lib.async"
local compile = require "coq.producers.snippets.compile"

local manifest_path = vim.fs.joinpath(repo_root, "config", "compilation.json")
local tmp_dir = vim.fs.joinpath(repo_root, ".vars", "tmp")
local out_dir = vim.fs.joinpath(repo_root, ".vars", "snippets", compile.OUT_DIR_NAME)

local err, stats = nil, nil

async.entry(function()
  local ok, ret = xpcall(function()
    return compile.run(manifest_path, tmp_dir, out_dir)
  end, debug.traceback)
  if ok then
    stats = ret
  else
    err = ret
  end
end)()

vim.wait(60 * 60 * 1000, function()
  return stats ~= nil or err ~= nil
end, 10)

if err then
  vim.notify(err, vim.log.levels.ERROR)
  os.exit(1)
end

assert(stats, "v3 compile did not complete")

if #stats.unknown > 0 then
  vim.notify("v3: unknown filetypes: " .. table.concat(stats.unknown, ", "), vim.log.levels.WARN)
end

if #stats.unused > 0 then
  vim.notify("v3: unused remaps: " .. table.concat(stats.unused, ", "), vim.log.levels.WARN)
end

local msg = string.format(
  "v3: files=%d kept=%d dropped=%d bundles=%d pruned=%d unknown=%d unused=%d -> %s",
  stats.files,
  stats.kept,
  stats.dropped,
  stats.bundles,
  stats.pruned,
  #stats.unknown,
  #stats.unused,
  out_dir
)
vim.notify(msg)
