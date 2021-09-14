from pynvim import Nvim
from pynvim_pp.keymap import Keymap
from pynvim_pp.settings import Settings

from ...registry import NAMESPACE, atomic, autocmd, rpc
from ...shared.settings import KeyMapping
from ..rt_types import Stack
from ..state import state
from .marks import nav_mark
from .omnifunc import omnifunc
from .preview import preview_preview
from .repeat import repeat
from .user_snippets import eval_snips


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


atomic.exec_lua(f"{NAMESPACE}.{_update_pumheight.name}()", ())
autocmd("VimResized") << f"lua {NAMESPACE}.{_update_pumheight.name}()"


def set_options(nvim: Nvim, mapping: KeyMapping, fast_close: bool) -> None:
    settings = Settings()
    keymap = Keymap()

    settings["completefunc"] = omnifunc.name

    if mapping.eval_snips:
        (
            keymap.n(mapping.eval_snips)
            << f"<cmd>lua {NAMESPACE}.{eval_snips.name}(false)<cr>"
        )
        (
            keymap.v(mapping.eval_snips)
            << rf"<c-\><c-n><cmd>lua {NAMESPACE}.{eval_snips.name}(true)<cr>"
        )

    if mapping.bigger_preview:
        (
            keymap.i(mapping.bigger_preview, expr=True)
            << f"(pumvisible() && complete_info(['mode']).mode ==# 'eval') ? {preview_preview.name}() : '{mapping.bigger_preview}'"
        )

    if mapping.jump_to_mark:
        keymap.n(mapping.jump_to_mark) << f"<cmd>lua {NAMESPACE}.{nav_mark.name}()<cr>"
        (
            keymap.iv(mapping.jump_to_mark)
            << rf"<c-\><c-n><cmd>lua {NAMESPACE}.{nav_mark.name}()<cr>"
        )

    if mapping.repeat:
        keymap.n(mapping.repeat) << f"<cmd>lua {NAMESPACE}.{repeat.name}()<cr>"

    if mapping.manual_complete:
        (
            keymap.i(mapping.manual_complete, expr=True)
            << "pumvisible() ? '<c-e><c-x><c-u>' : '<c-x><c-u>'"
        )
        keymap.nv(mapping.manual_complete) << r"<c-\><c-n>i<c-x><c-u>"

    if mapping.recommended:
        keymap.i("<esc>", expr=True) << "pumvisible() ? '<c-e><esc>' : '<esc>'"
        keymap.i("<c-c>", expr=True) << "pumvisible() ? '<c-e><c-c>' : '<c-c>'"
        keymap.i("<bs>", expr=True) << "pumvisible() ? '<c-e><bs>' : '<bs>'"
        keymap.i("<c-w>", expr=True) << "pumvisible() ? '<c-e><c-w>' : '<c-w>'"
        keymap.i("<c-u>", expr=True) << "pumvisible() ? '<c-e><c-u>' : '<c-u>'"
        (
            keymap.i("<cr>", expr=True)
            << "pumvisible() ? (complete_info(['selected']).selected == -1 ? '<c-e><cr>' : '<c-y>') : '<cr>'"
        )
        keymap.i("<tab>", expr=True) << "pumvisible() ? '<c-n>' : '<tab>'"
        keymap.i("<s-tab>", expr=True) << "pumvisible() ? '<c-p>' : '<bs>'"

    settings["completeopt"] += ("noinsert", "noselect", "menuone")
    if fast_close:
        settings["shortmess"] += "c"
    (settings.drain() + keymap.drain(buf=None)).commit(nvim)
