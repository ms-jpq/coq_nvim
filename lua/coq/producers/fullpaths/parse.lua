local path = require "coq.lib.path"

local M = {}

---@class fullpaths.parse.Opts
---@field is_windows boolean
---@field symbol string

---@class fullpaths.parse.Candidate
---@field start integer
---@field partial string
---@field local_sep string

---@param line_before string
---@param opts fullpaths.parse.Opts
---@return fullpaths.parse.Candidate?
M.candidate = function(line_before, opts)
  if opts.symbol == "" then
    return
  end
  local parts = vim.split(line_before, opts.symbol, { plain = true })
  if #parts < 2 then
    return
  end
  local partial = parts[#parts]
  return {
    start = #line_before - #opts.symbol - #partial,
    partial = partial,
    local_sep = path.local_sep(opts.is_windows, partial),
  }
end

return M
