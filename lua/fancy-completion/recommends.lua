local bindings = require "fancy-completion/bindings"


local map_keys = function ()

  -- escape key do not select candidate
  bindings.map.insert("<esc>", "pumvisible() ? '<c-e><esc>' : '<esc>'", {expr = true})

  -- backspace do not select candidate
  bindings.map.insert("<bs>",  "pumvisible() ? '<c-e><bs>'  : '<bs>'",  {expr = true})

  -- use enter key to select completion items
  bindings.map.insert("<cr>", "pumvisible() ? (complete_info().selected == -1 ? '<c-e><cr>' : '<c-y>') : '<cr>'",  {expr = true})

  -- use tabkeys to navigate completion menu
  bindings.map.insert("<tab>",   "pumvisible() ? '<c-n>' : '<tab>'", {expr = true})
  bindings.map.insert("<s-tab>", "pumvisible() ? '<c-p>' : '<bs>'",  {expr = true})

end


local settings = function ()

  -- complete menu options
  bindings.set("completeopt", "menu", [[-=]])
  bindings.set("completeopt", "menuone,noinsert,noselect", [[+=]])

  -- allow <c-x><c-u> to perform manual insertions in insertmode
  bindings.set("completefunc", "FComnifunc")

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
