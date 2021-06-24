from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from pynvim import Nvim
from pynvim_pp.api import buf_set_lines, create_buf
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, rpc
from ...shared.nvim.completions import VimCompletion
from ...shared.timeit import timeit
from ...shared.types import Doc
from ..runtime import Stack
from ..types import UserData


@dataclass(frozen=True)
class _Event:
    completed_item: VimCompletion[UserData]
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
        event.row + 1,
        event.height,
        event.col + event.width,
    )
    max_height = len(lines)
    max_width = max(map(len, lines))

    height = min(max_height, t_height - top - _MARGIN)
    width = min(max_width, t_width - left - _MARGIN)
    n = _Pos(
        row=1,
        col=left,
        height=height,
        width=width,
    )

    s = _Pos(
        row=btm + 1,
        col=left,
        height=height,
        width=width,
    )

    w = _Pos(
        row=1,
        col=1,
        height=height,
        width=width,
    )

    e = _Pos(
        row=top,
        col=right + 1,
        height=height,
        width=width,
    )
    return (n, s, w, e)


def _preview(nvim: Nvim, event: _Event, doc: Doc) -> None:
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
    buf_set_lines(nvim, buf=buf, lo=0, hi=-1, lines=lines)
    nvim.api.open_win(buf, True, opts)


@rpc(blocking=True)
def _cmp_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any] = {}) -> None:
    with timeit(0, "PREVIEW"):
        try:
            ev: _Event = decode(_Event, event, decoders=BUILTIN_DECODERS)
        except DecodeError:
            pass
        else:
            if (
                ev.completed_item.user_data
                and ev.completed_item.user_data.doc
                and ev.completed_item.user_data.doc.text
            ):
                _preview(nvim, event=ev, doc=ev.completed_item.user_data.doc)


autocmd("CompleteChanged") << f"lua {_cmp_changed.name}(vim.v.event)"

