(function(...)
  COQpreview = function(event)
    vim.schedule(function ()
      COQd_preview(event)
    end)
  end
end)(...)

