from pynvim import Nvim
from pynvim.api import Buffer, Window

from ..shared.types import Context
from .types import Expanded


def edit(nvim: Nvim, context: Context, expanded: Expanded) -> None:
    win: Window = nvim.api.get_current_win()
    buf: Buffer = nvim.api.get_current_buf()

    row = context.position.row
    lines = expanded.text.splitlines()
    nvim.api.buf_set_lines(buf, row, row + 1, True, lines)
    new_row, new_col = context.position.row, context.position.col
    nvim.api.win_set_cursor(win, (new_row + 1, new_col))
