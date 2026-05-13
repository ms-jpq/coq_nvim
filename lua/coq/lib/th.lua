local async = require "coq.lib.async"

return {
  run = async.wrap(function(fn, args, cb)
    local handle
    handle = vim.uv.new_async(function()
      handle:close()
      cb()
    end)
    vim.uv.new_thread(function(async_handle, fn_dump, ...)
      load(fn_dump)(...)
      async_handle:send()
    end, handle, string.dump(fn), unpack(args or {}))
  end),
}
