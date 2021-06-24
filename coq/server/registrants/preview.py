from dataclasses import dataclass
from typing import Any, Callable, Mapping, Sequence
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Window
from pynvim_pp.api import (
    create_buf,
    list_wins,
    win_close,
    win_get_var,
    win_set_option,
    win_set_var,
)
from pynvim_pp.preview import buf_set_preview
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, rpc
from ...shared.nvim.completions import VimCompletion
from ...shared.timeit import timeit
from ...shared.types import Doc
from ..runtime import Stack
from ..types import UserData

_FLOAT_WIN_UUID = uuid4().hex


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
_MIN = 4


def _kill_floating(nvim: Nvim) -> None:
    for win in list_wins(nvim):
        if win_get_var(nvim, win=win, key=_FLOAT_WIN_UUID):
            win_close(nvim, win=win)


@rpc(blocking=True)
def _kill_win(nvim: Nvim, stack: Stack) -> None:
    with timeit(0, "CURSOR MOVE"):
        _kill_floating(nvim)


autocmd("CursorMoved", "CursorMovedI") << f"lua {_kill_win.name}()"


def _clamp(hi: int) -> Callable[[int], int]:
    return lambda i: max(_MIN, min(hi, i) - _MARGIN)


def _positions(nvim: Nvim, event: _Event, lines: Sequence[str]) -> Sequence[_Pos]:
    t_height, t_width = nvim.options["lines"], nvim.options["columns"]
    top, btm, left, right = (
        event.row,
        event.row + event.height + 1,
        event.col,
        event.col + event.width + event.scrollbar,
    )
    limit_h, limit_w = _clamp(len(lines)), _clamp(max(map(len, lines)))

    ns_width = limit_w(t_width - right)
    n_height = limit_h(top - 1)

    ns_col = left - 1
    n = _Pos(
        row=top - 1 - n_height,
        col=ns_col,
        height=n_height,
        width=ns_width,
    )

    s = _Pos(
        row=btm,
        col=ns_col,
        height=limit_h(t_height - btm),
        width=ns_width,
    )

    we_height = limit_h(t_height - top)
    w_width = limit_w(left - 1)

    w = _Pos(
        row=top,
        col=left - w_width - 2,
        height=we_height,
        width=w_width,
    )

    e = _Pos(
        row=top,
        col=right + 2,
        height=we_height,
        width=limit_w(t_width - right - 2),
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
    buf_set_preview(nvim, buf=buf, filetype=doc.filetype, preview=lines)
    win: Window = nvim.api.open_win(buf, False, opts)
    win_set_option(nvim, win=win, key="wrap", val=True)
    win_set_option(nvim, win=win, key="foldenable", val=False)
    win_set_var(nvim, win=win, key=_FLOAT_WIN_UUID, val=True)
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
                _kill_floating(nvim)
                _preview(nvim, event=ev, doc=data.doc)


_LUA = f"""
(function()
  local event = vim.v.event
  vim.schedule(function() 
    {_cmp_changed.name}(event)
  end)
end)()
"""

autocmd("CompleteChanged") << f"lua {_LUA.strip()}"

