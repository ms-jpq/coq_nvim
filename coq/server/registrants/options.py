from pynvim import Nvim
from pynvim_pp.keymap import Keymap
from pynvim_pp.settings import Settings

from ...registry import atomic, autocmd, rpc
from ...shared.settings import KeyMapping
from ..runtime import Stack
from .marks import nav_mark
from .omnifunc import omnifunc


@rpc(blocking=True)
def _update_pumheight(nvim: Nvim, stack: Stack) -> None:
    lines: int = nvim.options["lines"]
    pumheight = max(
        round(lines * stack.settings.display.pum.y_ratio),
        stack.settings.display.pum.y_max_len,
    )
    nvim.options["pumheight"] = pumheight


atomic.exec_lua(f"{_update_pumheight.name}()", ())
autocmd("VimResized") << f"lua {_update_pumheight.name}()"


def set_options(nvim: Nvim, mapping: KeyMapping) -> None:
    settings = Settings()
    keymap = Keymap()

    settings["completefunc"] = omnifunc.name

    if mapping.manual_complete:
        (
            keymap.i(mapping.manual_complete, expr=True)
            << "pumvisible() ? '<c-e><c-x><c-u>' : '<c-x><c-u>'"
        )
    if mapping.jump_to_mark:
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

    (settings.drain() + keymap.drain(buf=None)).commit(nvim)

