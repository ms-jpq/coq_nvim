from dataclasses import dataclass
from typing import Any, Iterator, Mapping, Sequence

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


def _positions(nvim: Nvim, event: _Event, lines: Sequence[str]) -> Iterator[_Pos]:
    t_height, t_width = nvim.options["lines"], nvim.options["columns"]
    row, col = nvim.funcs.screenrow(), nvim.funcs.screencol()
    n, s, w, e = event.row, event.row + 1, event.height, event.col + event.width
    r, c = len(lines), max(map(len, lines))

    top = _Pos(
        row=1,
        col=1,
        height=1,
        width=1,
    )

    btm = _Pos(
        row=1,
        col=1,
        height=1,
        width=1,
    )

    lhs = _Pos(
        row=1,
        col=1,
        height=1,
        width=1,
    )

    rhs = _Pos(
        row=1,
        col=1,
        height=1,
        width=1,
    )
    yield from (top, btm, lhs, rhs)


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

