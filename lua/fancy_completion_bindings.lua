local api = vim.api


local set = function (opt, val, operator)
  local p_statement = function ()
    if not val then
      return "set " .. opt
    elseif not operator then
      return "set " .. opt .. "=" .. val
    else
      return "set " .. opt .. operator ..  val
    end
  end

  api.nvim_command(p_statement())
end


local map = function ()
  local base = {noremap = true, silent = true}

  local partial = function (prefix)
    return function (lhs, rhs, opt)
      local rhs = rhs or ""
      local opt = opt or {}
      local options = vim.tbl_extend("force", base, opt)
      if options.buffer then
        local buf = options.buffer
        options.buffer = nil
        for _, mode in ipairs(prefix) do
          api.nvim_buf_set_keymap(buf, mode, lhs, rhs, options)
        end
      else
        for _, mode in ipairs(prefix) do
          api.nvim_set_keymap(mode, lhs, rhs, options)
        end
      end
    end
  end

  return {
    normal = partial{"n"},
    command = partial{"c"},
    visual = partial{"v"},
    insert = partial{"i"},
    replace = partial{"r"},
    operator = partial{"o"},
    terminal = partial{"t"},
    no = partial{"n", "o"},
    nv = partial{"n", "v"},
    ni = partial{"n", "i"},
    nov = partial{"n", "o", "v"},
  }
end


return {
  set = set,
  map = map,
}
