from dataclasses import dataclass
from functools import partial
from typing import Any, Mapping, Sequence

from pynvim import Nvim
from pynvim.api import NvimError, Window
from pynvim_pp.api import buf_set_lines, buf_set_option, create_buf, win_set_option
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, enqueue_event, rpc
from ...shared.nvim.completions import VimCompletion
from ...shared.timeit import timeit
from ...shared.types import Doc
from ..runtime import Stack
from ..types import UserData


@dataclass(frozen=True)
class _Event:
    completed_item: VimCompletion
    row: int
    col: int
    height: int
    width: int
    size: int
    scrollbar: bool


@dataclass(frozen=True)
class _Pos:
    row: int
    col: int
    height: int
    width: int


_MARGIN = 4


def _positions(nvim: Nvim, event: _Event, lines: Sequence[str]) -> Sequence[_Pos]:
    t_height, t_width = nvim.options["lines"], nvim.options["columns"]
    top, btm, left, right = (
        event.row,
        event.row + event.height + 1,
        event.col,
        event.col + event.width + 1,
    )
    limit_h, limit_w = partial(min, len(lines)), partial(min, max(map(len, lines)))
    limit_h = limit_w = lambda x: x

    ns_width = limit_w(t_width - right)
    n_height = limit_h(top - 1)

    ns_col = left - 1
    n = _Pos(
        row=top + 1 - n_height,
        col=ns_col,
        height=n_height,
        width=ns_width,
    )

    s = _Pos(
        row=btm + 1,
        col=ns_col,
        height=limit_h(t_height - btm),
        width=ns_width,
    )

    we_height = limit_h(t_height - top)
    w_width = limit_w(left)

    w = _Pos(
        row=top,  # OK
        col=left - w_width,
        height=we_height,
        width=w_width,
    )

    e = _Pos(
        row=top,  # OK
        col=right + 1,  # OK
        height=we_height,
        width=limit_w(t_width - right),
    )
    return (n, s, w, e)


@rpc(blocking=True)
def _preview(nvim: Nvim, stack: Stack, event: _Event, doc: Doc) -> None:
    lines = doc.text.splitlines()
    pos, *_ = sorted(
        _positions(nvim, event=event, lines=lines),
        key=lambda p: p.height * p.width,
        reverse=True,
    )
    opts = {
        "relative": "editor",
        "anchor": "NW",
        "style": "minimal",
        "width": pos.width,
        "height": pos.height,
        "row": pos.row,
        "col": pos.col,
    }
    buf = create_buf(
        nvim, listed=False, scratch=True, wipe=True, nofile=True, noswap=True
    )
    buf_set_option(nvim, buf=buf, key="buftype", val="nofile")
    buf_set_option(nvim, buf=buf, key="filetype", val=doc.filetype)
    buf_set_option(nvim, buf=buf, key="modifiable", val=True)
    while True:
        try:
            buf_set_lines(nvim, buf=buf, lo=0, hi=-1, lines=lines)
        except NvimError:
            pass
        else:
            break
    buf_set_option(nvim, buf=buf, key="modifiable", val=False)

    while True:
        try:
            win: Window = nvim.api.open_win(buf, False, opts)
        except NvimError:
            pass
        else:
            break
    win_set_option(nvim, win=win, key="wrap", val=True)
    win_set_option(nvim, win=win, key="foldenable", val=False)
    # win_set_option(nvim, win=win, key="winhighlight", val="Normal:Floating")


@rpc(blocking=True)
def _cmp_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any] = {}) -> None:
    with timeit(0, "PREVIEW"):
        try:
            ev: _Event = decode(_Event, event)
            data: UserData = decode(
                UserData, ev.completed_item.user_data, decoders=BUILTIN_DECODERS
            )
        except DecodeError:
            pass
        else:
            if data and data.doc and data.doc.text:
                enqueue_event(_preview, ev, data.doc)
                # _preview(nvim, event=ev, doc=data.doc)


autocmd("CompleteChanged") << f"lua {_cmp_changed.name}(vim.v.event)"

