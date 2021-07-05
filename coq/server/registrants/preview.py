from concurrent.futures import CancelledError, Future, TimeoutError
from dataclasses import dataclass
from os import linesep
from typing import (
    Any,
    Callable,
    Iterator,
    Mapping,
    MutableSequence,
    Optional,
    Sequence,
    Tuple,
)
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
from pynvim_pp.logging import log
from pynvim_pp.preview import buf_set_preview, set_preview
from std2.ordinal import clamp
from std2.pickle import DecodeError, new_decoder

from ...lsp.requests.preview import request
from ...lsp.types import CompletionItem
from ...registry import autocmd, enqueue_event, rpc
from ...shared.settings import PreviewDisplay
from ...shared.timeit import timeit
from ...shared.trans import expand_tabs
from ...shared.types import UTF8, Context, Doc
from ..nvim.completions import VimCompletion
from ..rt_types import Stack
from ..state import State, state

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
    display: PreviewDisplay,
    event: _Event,
    lines: Sequence[str],
    state: State,
) -> Sequence[_Pos]:
    scr_width, src_height = state.screen
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

    ns_width = limit_w(scr_width - left)
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
        height=limit_h(src_height - btm),
        width=ns_width,
    )

    we_height = limit_h(src_height - top)
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
        width=limit_w(scr_width - right - 2),
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


@rpc(blocking=True)
def _show_preview(
    nvim: Nvim, stack: Stack, event: _Event, doc: Doc, state: State
) -> None:
    new_doc = _preprocess(state.context, doc=doc)
    text = expand_tabs(state.context, text=new_doc.text)
    lines = text.splitlines()
    (_, pos), *_ = sorted(
        enumerate(
            _positions(
                stack.settings.display.preview, event=event, lines=lines, state=state
            )
        ),
        key=lambda p: (p[1].height * p[1].width, -p[0]),
        reverse=True,
    )

    buf = create_buf(
        nvim, listed=False, scratch=True, wipe=True, nofile=True, noswap=True
    )
    buf_set_preview(nvim, buf=buf, syntax=new_doc.syntax, preview=lines)
    _set_win(nvim, buf=buf, pos=pos)


_FUTS: MutableSequence[Future] = []


def _resolve_comp(
    nvim: Nvim,
    stack: Stack,
    event: _Event,
    item: CompletionItem,
    maybe_doc: Optional[Doc],
    state: State,
) -> None:
    f1 = stack.supervisor.pool.submit(request, nvim, item)
    _FUTS.append(f1)

    def cont() -> None:
        try:
            doc = None
            try:
                doc = f1.result(timeout=stack.settings.display.preview.lsp_timeout)
            except CancelledError:
                pass
            except TimeoutError:
                doc = maybe_doc

            if doc:
                enqueue_event(_show_preview, event, doc, state)
        except Exception as e:
            log.exception("%s", e)

    f2 = stack.supervisor.pool.submit(cont)
    _FUTS.append(f2)


_DECODER = new_decoder(_Event)


@rpc(blocking=True)
def _cmp_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any] = {}) -> None:
    for fut in _FUTS:
        fut.cancel()
    _FUTS.clear()

    _kill_win(nvim, stack=stack)
    with timeit("PREVIEW"):
        try:
            ev: _Event = _DECODER(event)
        except DecodeError:
            pass
        else:
            data = ev.completed_item.user_data
            if data:
                s = state()
                if data.doc and data.doc.text:
                    _show_preview(nvim, stack=stack, event=ev, doc=data.doc, state=s)
                elif data.extern:
                    _resolve_comp(
                        nvim,
                        stack=stack,
                        event=ev,
                        item=data.extern,
                        maybe_doc=data.doc,
                        state=s,
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

