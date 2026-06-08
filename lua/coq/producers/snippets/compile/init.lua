local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local hacks = require "coq.producers.snippets.compile.hacks"
local json = require "coq.lib.json"
local lib = require "coq.lib"
local parse = require "coq.producers.snippets.compile.parse"
local queue_m = require "coq.lib.queue"
local set = require "coq.lib.set"
local txt = require "coq.lib.text"

local M = {}

M.OUT_DIR_NAME = "coq+snippets+v3"

---@class snippets.CompManifest
---@field git string[]
---@field paths { lsp: string[], neosnippet: string[], ultisnip: string[] }
---@field remaps table<string, string[]>

---@class snippets.BundleV3
---@field extends string[]
---@field snippets snippets.BundleEntry[]

local LSP_EXTS = { ".json" }
local SNU_EXTS = { ".snippets", ".snip" }

---@param ft string
---@return string
M.bundle_filename = function(ft)
  return string.lower(ft) .. ".json"
end

---@param body string
---@return boolean ok
M._validate = function(body)
  atools.scheduled()
  return (pcall(vim.lsp._snippet_grammar.parse, body))
end

---@param dir string
---@param exts string[]
---@return fun() close
---@return lib.Iterator<string> iter
local walk_ext = function(dir, exts)
  return closable.iter(function(defer)
    local close, iter = atools.fs.walk(dir)
    defer(close)
    for file, kind in iter do
      if kind == "file" and txt.endswith(exts, file) then
        coroutine.yield(file)
      end
    end
  end)
end

---@param exts_by_ft table<string, lib.Set<string>>
---@param ft string
---@param parent string
---@return table<string, lib.Set<string>>
local add_ext = function(exts_by_ft, ft, parent)
  if parent == "" or parent == ft then
    return exts_by_ft
  end
  local lowered = string.lower(parent)
  local bag = vim.tbl_extend("force", exts_by_ft[ft] or set.new {}, { [lowered] = true })
  return vim.tbl_extend("force", exts_by_ft, { [ft] = bag })
end

---@param exts_by_ft table<string, lib.Set<string>>
---@param remaps table<string, string[]>
---@return table<string, lib.Set<string>>
local apply_remaps = function(exts_by_ft, remaps)
  local acc = exts_by_ft
  for parent, children in pairs(remaps or {}) do
    for _, child in pairs(children) do
      acc = add_ext(acc, string.lower(child), parent)
    end
  end
  return acc
end

---@return lib.Set<string>
local known_filetypes = function()
  atools.scheduled()
  local seen = set.new {}
  for _, ft in ipairs(vim.fn.getcompletion("", "filetype")) do
    seen[ft] = true
  end
  local inspect = vim.filetype.inspect()
  for _, map in pairs { inspect.extension, inspect.filename, inspect.pattern } do
    for _, v in pairs(map) do
      local ft = type(v) == "table" and v[1] or v
      if type(ft) == "string" then
        seen[ft] = true
      end
    end
  end
  return seen
end

---@param known lib.Set<string>
---@param bundles table<string, snippets.BundleV3>
---@return string[]
local unknown_filetypes = function(known, bundles)
  local covered = set.new {}
  local queue = queue_m.new()
  for ft in pairs(bundles) do
    if known[ft] then
      covered[ft] = true
      queue.push(ft)
    end
  end
  for ft in queue.pop do
    local bundle = bundles[ft]
    if bundle then
      for _, parent in pairs(bundle.extends) do
        if not covered[parent] then
          covered[parent] = true
          queue.push(parent)
        end
      end
    end
  end

  ---@type string[]
  local unknown = vim
    .iter(bundles)
    :map(function(ft, _)
      return (not covered[ft]) and ft or nil
    end)
    :totable()
  table.sort(unknown)
  return unknown
end

---@param remaps table<string, string[]>
---@param bundles table<string, snippets.BundleV3>
---@return string[]
local unused_remaps = function(remaps, bundles)
  ---@type string[]
  local unused = vim
    .iter(remaps or {})
    :map(function(key, _)
      local bundle = bundles[key]
      return (not bundle or #bundle.snippets == 0) and key or nil
    end)
    :totable()
  table.sort(unused)
  return unused
end

---@param items_by_ft table<string, snippets.BundleEntry[]>
---@param exts_by_ft table<string, lib.Set<string>>
---@return table<string, snippets.BundleV3>
local assemble = function(items_by_ft, exts_by_ft)
  ---@type table<string, snippets.BundleV3>
  local bundles = {}
  for ft in pairs(vim.tbl_extend("force", items_by_ft, exts_by_ft)) do
    local extends = vim.tbl_keys(exts_by_ft[ft] or set.new {})
    table.sort(extends)
    bundles[ft] = { extends = extends, snippets = items_by_ft[ft] or {} }
  end
  return bundles
end

---@param tmp_dir string
---@param subs string[]
---@param exts string[]
---@param parser fun(file: string, text: string): (string, string[], snippets.BundleEntry[])
---@param on_file fun(ft: string, parents: string[], entries: snippets.BundleEntry[])
local walk_subs = function(tmp_dir, subs, exts, parser, on_file)
  lib.scope(function(defer)
    for _, sub in pairs(subs) do
      local close, iter = walk_ext(vim.fs.joinpath(tmp_dir, sub), exts)
      defer(close)
      for file in iter do
        on_file(parser(file, atools.fs.slurp(file) or ""))
      end
    end
  end)
end

---@param tmp_dir string
---@param manifest snippets.CompManifest
---@return table<string, snippets.BundleV3> bundles
---@return { kept: integer, dropped: integer, files: integer } stats
M._compile = function(tmp_dir, manifest)
  local stats = { kept = 0, dropped = 0, files = 0 }
  ---@type table<string, lib.Set<string>>
  local exts_by_ft = {}
  ---@type table<string, snippets.BundleEntry[]>
  local items_by_ft = {}

  ---@param ft string
  ---@param entry snippets.BundleEntry
  local consume = function(ft, entry)
    entry = hacks.trans(ft, entry)
    local content = entry.content
    local ok = type(content) == "string" and content ~= "" and M._validate(content)
    if not ok then
      stats.dropped = stats.dropped + 1
      return
    end
    stats.kept = stats.kept + 1
    local bucket = items_by_ft[ft] or {}
    table.insert(bucket, entry)
    items_by_ft[ft] = bucket
  end

  ---@param ft string
  ---@param parents string[]
  ---@param entries snippets.BundleEntry[]
  local on_file = function(ft, parents, entries)
    stats.files = stats.files + 1
    for _, p in pairs(parents) do
      exts_by_ft = add_ext(exts_by_ft, ft, p)
    end
    for _, e in pairs(entries) do
      consume(ft, e)
    end
  end

  local paths = manifest.paths or {}
  local snu_subs = vim.iter({ paths.neosnippet or {}, paths.ultisnip or {} }):flatten():totable()

  walk_subs(tmp_dir, paths.lsp or {}, LSP_EXTS, parse.lsp, on_file)
  walk_subs(tmp_dir, snu_subs, SNU_EXTS, parse.neosnippet_like, on_file)
  exts_by_ft = apply_remaps(exts_by_ft, manifest.remaps)

  return assemble(items_by_ft, exts_by_ft), stats
end

---@param manifest_path string
---@param tmp_dir string
---@param out_dir string
---@return { kept: integer, dropped: integer, files: integer, bundles: integer, pruned: integer, unknown: string[], unused: string[] }
M.run = function(manifest_path, tmp_dir, out_dir)
  return lib.scope(function(defer)
    local raw = atools.fs.slurp(manifest_path)
    assert(raw, "cannot read " .. manifest_path)

    atools.scheduled()
    local known_ft = known_filetypes()
    local manifest, json_err = json.decode(raw)
    assert(manifest, json_err)
    local bundles, stats = M._compile(tmp_dir, manifest)
    local unknown = unknown_filetypes(known_ft, bundles)
    local unused = unused_remaps(manifest.remaps, bundles)

    atools.fs.mkdirp(out_dir)
    local written = set.new {}
    for ft, bundle in pairs(bundles) do
      local file = vim.fs.joinpath(out_dir, M.bundle_filename(ft))
      written[file] = true
      local spit_err = atools.fs.spit(file, json.encode(bundle, true))
      assert(not spit_err, "cannot write " .. file .. ": " .. tostring(spit_err))
    end

    local close, iter = atools.fs.scandir(out_dir)
    defer(close)
    ---@type string[]
    local stale = vim
      .iter(iter)
      :map(function(name, kind)
        if kind ~= "file" then
          return nil
        end
        local file = vim.fs.joinpath(out_dir, name)
        return (not written[file]) and file or nil
      end)
      :totable()

    for _, file in pairs(stale) do
      local _ = atools.fs.unlink(file)
    end

    return {
      kept = stats.kept,
      dropped = stats.dropped,
      files = stats.files,
      bundles = vim.tbl_count(bundles),
      pruned = #stale,
      unknown = unknown,
      unused = unused,
    }
  end)
end

return M
