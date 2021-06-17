from typing import Iterator, Sequence, Tuple

from pynvim import Nvim
from pynvim.api.nvim import Nvim
from pynvim_pp.api import cur_win, win_get_buf

from ...consts import NS
from ...registry import rpc
from ...shared.types import Mark
from ..runtime import Stack


def _ls_marks(nvim: Nvim) -> None:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    ns = nvim.api.create_namespace(NS)
    marks: Sequence[Tuple[str, int, int]] = nvim.api.buf_get_extmarks(
        buf, ns, 0, -1, {"details": True}
    )

    print(marks, flush=True)


@rpc(blocking=True)
def prev_mark(nvim: Nvim, stack: Stack) -> None:
    _ls_marks(nvim)


@rpc(blocking=True)
def next_mark(nvim: Nvim, stack: Stack) -> None:
    _ls_marks(nvim)

