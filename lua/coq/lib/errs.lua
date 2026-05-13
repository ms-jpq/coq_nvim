local M = {}

M.UNKNOWN = "unknown error"

M.group = function(es)
  return setmetatable({ errs = es }, {
    __tostring = function(self)
      local parts = { ("error group (%d errors):"):format(#self.errs) }
      for i, e in ipairs(self.errs) do
        table.insert(parts, ("  [%d] %s"):format(i, tostring(e)))
      end
      return table.concat(parts, "\n")
    end,
  })
end

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
