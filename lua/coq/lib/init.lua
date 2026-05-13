return {
  scope = function(fn)
    local defers = {}
    local ok, ret = pcall(fn, function(defer)
      table.insert(defers, defer)
    end)

    for defer in vim.iter(defers):rev() do
      local ok, err = pcall(defer)
      if not ok then
        vim.notify(err, vim.log.levels.ERROR)
      end
    end

    if ok then
      return ret
    else
      error(ret, 0)
    end
  end,
}
