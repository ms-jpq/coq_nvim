---@class ErrorGroup
---@field errs any[]

local M = {}

M.UNKNOWN = "unknown error"

---@param es any[]
---@return ErrorGroup
M.group = function(es)
  return setmetatable({ errs = es }, {
    __tostring = function(self)
      local header = ("error group (%d errors):"):format(#self.errs)
      local body = vim
        .iter(self.errs)
        :enumerate()
        :map(function(i, e)
          return ("  [%d] %s"):format(i, tostring(e))
        end)
        :totable()
      return header .. "\n" .. table.concat(body, "\n")
    end,
  })
end

---@param es any[]
M.raise = function(es)
  if #es == 0 then
    return
  elseif #es == 1 then
    error(es[1], 0)
  else
    error(M.group(es), 0)
  end
end

return M
