local std = require "fancy_completion_std"


local map_keys = function ()

  -- escape key do not select candidate
  std.map.insert("<esc>", "pumvisible() ? '<c-e><esc>' : '<esc>'", {expr = true})

  -- backspace do not select candidate
  std.map.insert("<bs>",  "pumvisible() ? '<c-e><bs>'  : '<bs>'",  {expr = true})

  -- use enter key to select completion items
  std.map.insert("<cr>", "pumvisible() ? (complete_info().selected == -1 ? '<c-e><cr>' : '<c-y>') : '<cr>'",  {expr = true})

  -- use tabkeys to navigate completion menu
  std.map.insert("<tab>",   "pumvisible() ? '<c-n>' : '<tab>'", {expr = true})
  std.map.insert("<s-tab>", "pumvisible() ? '<c-p>' : '<bs>'",  {expr = true})
end


return {
  map_keys = map_keys()
}
