from pynvim import Nvim
from pynvim_pp.keymap import Keymap
from pynvim_pp.settings import Settings

from ..shared.settings import KeyMapping
from .registrants.marks import nav_mark
from .registrants.omnifunc import omnifunc


def set_options(nvim: Nvim, mapping: KeyMapping) -> None:
    settings = Settings()
    keymap = Keymap()

    settings["completefunc"] = omnifunc.name
    keymap.n(mapping.jump_to_mark) << f"<cmd>lua {nav_mark.name}()<cr>"
    keymap.v(mapping.jump_to_mark) << f"<esc><cmd>lua {nav_mark.name}()<cr>"

    if mapping.recommended:
        settings["shortmess"] += "c"
        settings["completeopt"] += ("noinsert", "noselect", "menuone")

        keymap.i("<esc>", expr=True) << "pumvisible() ? '<c-e><esc>' : '<esc>'"
        keymap.i("<bs>", expr=True) << "pumvisible() ? '<c-e><bs>' : '<bs>'"
        (
            keymap.i("<cr>", expr=True)
            << "pumvisible() ? (complete_info().selected == -1 ? '<c-e><cr>' : '<c-y>') : '<cr>'"
        )
        keymap.i("<tab>", expr=True) << "pumvisible() ? '<c-n>' : '<tab>'"
        keymap.i("<s-tab>", expr=True) << "pumvisible() ? '<c-p>' : '<bs>'"

    keymap.drain(buf=None).commit(nvim)

