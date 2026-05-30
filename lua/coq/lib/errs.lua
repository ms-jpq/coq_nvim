---@class lib.ErrorGroup<T>
---@field errs T[]

local M = {}

M.UNKNOWN = "unknown error"

---@generic T
---@param es T[]
---@return lib.ErrorGroup<T>
M.group = function(es)
  return setmetatable({ errs = es }, {
    __tostring = function(self)
      local header = string.format("error group (%d errors):", #self.errs)
      local body = vim
        .iter(self.errs)
        :enumerate()
        :map(function(i, e)
          return string.format("  [%d] %s", i, tostring(e))
        end)
        :totable()
      return header .. "\n" .. table.concat(body, "\n")
    end,
  })
end

---@generic T
---@param es T[]
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
