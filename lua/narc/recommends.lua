local bindings = require "narc/bindings"


local map_keys = function ()
  
  local map = bindings.map()
  -- escape key do not select candidate
  map.insert("<esc>", "pumvisible() ? '<c-e><esc>' : '<esc>'", {expr = true})

  -- backspace do not select candidate
  map.insert("<bs>",  "pumvisible() ? '<c-e><bs>'  : '<bs>'",  {expr = true})

  -- use enter key to select completion items
  map.insert("<cr>", "pumvisible() ? (complete_info().selected == -1 ? '<c-e><cr>' : '<c-y>') : '<cr>'",  {expr = true})

  -- use tabkeys to navigate completion menu
  map.insert("<tab>",   "pumvisible() ? '<c-n>' : '<tab>'", {expr = true})
  map.insert("<s-tab>", "pumvisible() ? '<c-p>' : '<bs>'",  {expr = true})

  -- use <c-space> to force completion
  map.nv("<c-space>")
  map.insert("<c-space>", "<c-x><c-u>")

end


local settings = function ()

  -- complete menu options
  bindings.set("completeopt", "menu", [[-=]])
  bindings.set("completeopt", "menuone,noinsert,noselect", [[+=]])

  -- allow <c-x><c-u> to perform manual insertions in insertmode
  bindings.set("completefunc", "NARComnifunc")

end


local all = function ()
  map_keys()
  settings()
end


return {
  map_keys = map_keys,
  settings = settings,
  all = all,
}
