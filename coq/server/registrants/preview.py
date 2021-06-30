from dataclasses import dataclass
from os import linesep
from typing import Any, Callable, Iterator, Mapping, Sequence, Tuple
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer, Window
from pynvim_pp.api import (
    buf_get_lines,
    buf_get_option,
    create_buf,
    list_wins,
    win_close,
    win_get_buf,
    win_get_var,
    win_set_option,
    win_set_var,
)
from pynvim_pp.preview import buf_set_preview, set_preview
from std2.ordinal import clamp
from std2.pickle import DecodeError, decode
from std2.pickle.coders import BUILTIN_DECODERS

from ...registry import autocmd, rpc
from ...shared.nvim.completions import VimCompletion
from ...shared.settings import PreviewDisplay
from ...shared.timeit import timeit
from ...shared.trans import expand_tabs
from ...shared.types import UTF8, Context, Doc
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


def _ls(nvim: Nvim) -> Iterator[Window]:
    for win in list_wins(nvim):
        if win_get_var(nvim, win=win, key=_FLOAT_WIN_UUID):
            yield win


@rpc(blocking=True)
def _kill_win(nvim: Nvim, stack: Stack) -> None:
    for win in _ls(nvim):
        win_close(nvim, win=win)


autocmd("CompleteDone", "InsertLeave") << f"lua {_kill_win.name}()"


def _preprocess(context: Context, doc: Doc) -> Doc:
    if doc.syntax == "markdown":
        split = doc.text.splitlines()
        if split and split[0] == "```" and split[-1] == "```":
            text = linesep.join(split[1:-1])
            return Doc(text=text, syntax=context.filetype)
        else:
            return doc
    else:
        return doc


def _clamp(margin: int, hi: int) -> Callable[[int], int]:
    return lambda i: clamp(1, i - margin, hi)


def _positions(
    stack: Stack,
    display: PreviewDisplay,
    event: _Event,
    lines: Sequence[str],
) -> Sequence[_Pos]:
    (
        t_width,
        t_height,
    ) = stack.state.screen
    top, btm, left, right = (
        event.row,
        event.row + event.height + 1,
        event.col,
        event.col + event.width + event.scrollbar,
    )
    limit_h, limit_w = (
        _clamp(display.margin, hi=len(lines)),
        _clamp(display.margin, hi=max(len(line.encode(UTF8)) for line in lines)),
    )

    ns_width = limit_w(t_width - left)
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
    return n, s, w, e


def _set_win(nvim: Nvim, buf: Buffer, pos: _Pos) -> None:
    opts = {
        "relative": "editor",
        "anchor": "NW",
        "style": "minimal",
        "width": pos.width,
        "height": pos.height,
        "row": pos.row,
        "col": pos.col,
    }
    win: Window = nvim.api.open_win(buf, False, opts)
    win_set_option(nvim, win=win, key="wrap", val=True)
    win_set_var(nvim, win=win, key=_FLOAT_WIN_UUID, val=True)


def _preview(
    nvim: Nvim,
    stack: Stack,
    context: Context,
    display: PreviewDisplay,
    event: _Event,
    doc: Doc,
) -> None:
    new_doc = _preprocess(context, doc=doc)

    text = expand_tabs(context, text=new_doc.text)
    lines = text.splitlines()
    (_, pos), *_ = sorted(
        enumerate(_positions(stack, display=display, event=event, lines=lines)),
        key=lambda p: (p[1].height * p[1].width, -p[0]),
        reverse=True,
    )

    buf = create_buf(
        nvim, listed=False, scratch=True, wipe=True, nofile=True, noswap=True
    )
    buf_set_preview(nvim, buf=buf, syntax=new_doc.syntax, preview=lines)
    _set_win(nvim, buf=buf, pos=pos)


@rpc(blocking=True)
def _cmp_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any] = {}) -> None:
    _kill_win(nvim, stack=stack)
    with timeit("PREVIEW"):
        try:
            ev: _Event = decode(_Event, event)
            data: UserData = decode(
                UserData, ev.completed_item.user_data, decoders=BUILTIN_DECODERS
            )
        except DecodeError:
            pass
        else:
            if stack.state.cur and data and data.doc and data.doc.text:
                _preview(
                    nvim,
                    stack=stack,
                    context=stack.state.cur,
                    display=stack.settings.display.preview,
                    event=ev,
                    doc=data.doc,
                )


_LUA_1 = f"""
(function()
  local event = vim.v.event
  vim.schedule(function() 
    {_cmp_changed.name}(event)
  end)
end)(...)
""".strip()

autocmd("CompleteChanged") << f"lua {_LUA_1}"


@rpc(blocking=True)
def _bigger_preview(nvim: Nvim, stack: Stack, args: Tuple[str, Sequence[str]]) -> None:
    syntax, lines = args
    nvim.command("stopinsert")
    set_preview(nvim, syntax=syntax, preview=lines)


_LUA_2 = f"""
(function(syntax, lines)
  local event = vim.v.event
  vim.schedule(function() 
    {_bigger_preview.name}(syntax, lines)
  end)
end)(...)
""".strip()


@rpc(blocking=True)
def preview_preview(nvim: Nvim, stack: Stack, *_: str) -> str:
    win = next(_ls(nvim), None)
    if win:
        buf = win_get_buf(nvim, win=win)
        syntax = buf_get_option(nvim, buf=buf, key="syntax")
        lines = buf_get_lines(nvim, buf=buf, lo=0, hi=-1)
        nvim.exec_lua(_LUA_2, (syntax, lines))

    escaped: str = nvim.api.replace_termcodes("<c-e>", True, False, True)
    return escaped

