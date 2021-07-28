from pynvim import Nvim
from pynvim_pp.keymap import Keymap
from pynvim_pp.settings import Settings

from ...registry import atomic, autocmd, rpc
from ...shared.settings import KeyMapping
from ..rt_types import Stack
from ..state import state
from .marks import nav_mark
from .omnifunc import omnifunc
from .preview import preview_preview


@rpc(blocking=True)
def _update_pumheight(nvim: Nvim, stack: Stack) -> None:
    scr_width: int = nvim.options["columns"]
    scr_height: int = nvim.options["lines"]
    state(screen=(scr_width, scr_height))

    pumheight = max(
        round(scr_height * stack.settings.display.pum.y_ratio),
        stack.settings.display.pum.y_max_len,
    )
    nvim.options["pumheight"] = pumheight


atomic.exec_lua(f"{_update_pumheight.name}()", ())
autocmd("VimResized") << f"lua {_update_pumheight.name}()"


def set_options(nvim: Nvim, mapping: KeyMapping) -> None:
    settings = Settings()
    keymap = Keymap()

    settings["completefunc"] = omnifunc.name

    if mapping.jump_to_mark:
        keymap.n(mapping.jump_to_mark) << f"<cmd>lua {nav_mark.name}()<cr>"
        keymap.iv(mapping.jump_to_mark) << f"<esc><cmd>lua {nav_mark.name}()<cr>"

    if mapping.bigger_preview:
        (
            keymap.i(mapping.bigger_preview, expr=True)
            << f"pumvisible() ? {preview_preview.name}() : '{mapping.bigger_preview}'"
        )

    if mapping.manual_complete:
        (
            keymap.i(mapping.manual_complete, expr=True)
            << "pumvisible() ? '<c-e><c-x><c-u>' : '<c-x><c-u>'"
        )
        keymap.nv(mapping.manual_complete) << "<esc>i<c-x><c-u>"

    if mapping.recommended:
        keymap.i("<esc>", expr=True) << "pumvisible() ? '<c-e><esc>' : '<esc>'"
        keymap.i("<bs>", expr=True) << "pumvisible() ? '<c-e><bs>' : '<bs>'"
        (
            keymap.i("<cr>", expr=True)
            << "pumvisible() ? (complete_info().selected == -1 ? '<c-e><cr>' : '<c-y>') : '<cr>'"
        )
        keymap.i("<tab>", expr=True) << "pumvisible() ? '<c-n>' : '<tab>'"
        keymap.i("<s-tab>", expr=True) << "pumvisible() ? '<c-p>' : '<bs>'"

    settings["completeopt"] += ("noinsert", "noselect", "menuone")
    settings["shortmess"] += "c"
    settings["noshowmode"] = True
    (settings.drain() + keymap.drain(buf=None)).commit(nvim)
