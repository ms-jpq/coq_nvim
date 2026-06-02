local atools = require "coq.lib.atools"

local M = {}

local FIELDS = {
  "language",
  "input",
  "line",
  "kind",
  "name",
  "pattern",
  "typeref",
  "scope",
  "scopeKind",
  "access",
  "signature",
}

local FIELDS_ARG = "--fields="
  .. table.concat(
    vim.tbl_map(function(f)
      return "{" .. f .. "}"
    end, FIELDS),
    ""
  )

---@param bin string
---@param paths string[]
---@return string?
M.run = function(bin, paths)
  if #paths == 0 then
    return nil
  end

  local argv = { bin, "--sort=no", "--output-format=json", FIELDS_ARG }
  for _, p in pairs(paths) do
    table.insert(argv, p)
  end

  local proc = atools.spawn(argv)
  if proc == nil then
    return nil
  end
  return proc.stdout
end

return M
