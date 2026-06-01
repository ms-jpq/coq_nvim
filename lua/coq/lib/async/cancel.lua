---@class async.Cancel

local CANCEL_EFF = {
  __tostring = function()
    return "<cancelled>"
  end,
}

local M = {}

---@return async.Cancel
M.new = function()
  return setmetatable({}, CANCEL_EFF)
end

---@param x any
---@return boolean
M.is = function(x)
  return type(x) == "table" and getmetatable(x) == CANCEL_EFF
end

---@param fn fun(...): any
---@param ... any
---@return boolean ok, any ...
M.pcall = function(fn, ...)
  local go = function(ok, ...)
    if not ok and M.is((...)) then
      error((...), 0)
    end
    return ok, ...
  end
  return go(pcall(fn, ...))
end

---@param fn fun(...): any
---@param handler fun(err: any): any
---@param ... any
---@return boolean ok, any ...
M.xpcall = function(fn, handler, ...)
  local go = function(ok, ...)
    if not ok and M.is((...)) then
      error((...), 0)
    end
    return ok, ...
  end
  return go(xpcall(fn, function(err)
    if M.is(err) then
      return err
    end
    return handler(err)
  end, ...))
end

return M
