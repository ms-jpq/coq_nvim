from asyncio import Task, wait
from dataclasses import asdict, dataclass
from itertools import chain
from math import ceil
from os import linesep
from pathlib import Path
from typing import (
    Any,
    Callable,
    Iterator,
    Mapping,
    Optional,
    Sequence,
    Tuple,
    Union,
    cast,
)
from uuid import UUID, uuid4

from pynvim import Nvim
from pynvim.api import Buffer, Window
from pynvim_pp.api import (
    ExtMark,
    buf_get_lines,
    buf_get_option,
    buf_set_extmarks,
    clear_ns,
    create_buf,
    create_ns,
    cur_buf,
    cur_win,
    list_wins,
    win_close,
    win_get_buf,
    win_get_cursor,
    win_get_var,
    win_set_option,
    win_set_var,
)
from pynvim_pp.float_win import border_w_h
from pynvim_pp.lib import async_call, display_width, go
from pynvim_pp.preview import buf_set_preview, set_preview
from std2 import clamp
from std2.asyncio import cancel
from std2.pickle import DecodeError, new_decoder
from std2.string import removeprefix

from ...lsp.requests.preview import request
from ...lsp.types import CompletionItem
from ...paths.show import show
from ...registry import autocmd, rpc
from ...shared.settings import GhostText, PreviewDisplay
from ...shared.timeit import timeit
from ...shared.trans import expand_tabs
from ...shared.types import Completion, Context, Doc, Edit, Extern
from ..nvim.completions import VimCompletion
from ..rt_types import Stack
from ..state import State, state

_FLOAT_WIN_UUID = uuid4().hex
_NS = uuid4()


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
def _kill_win(nvim: Nvim, stack: Stack, reset: bool) -> None:
    if reset:
        state(pum_location=None, preview_id=uuid4())

    buf = cur_buf(nvim)
    ns = create_ns(nvim, ns=_NS)
    clear_ns(nvim, buf=buf, id=ns)

    for win in _ls(nvim):
        win_close(nvim, win=win)


autocmd("CompleteDone", "InsertLeave") << f"lua {_kill_win.name}(true)"


def _preprocess(context: Context, doc: Doc) -> Doc:
    sep = "```"
    if doc.syntax == "markdown":
        split = doc.text.splitlines()
        if (
            split
            and split[0].startswith(sep)
            and split[-1].startswith(sep)
            and not sum(line.startswith(sep) for line in split[1:-1])
        ):
            text = linesep.join(split[1:-1])
            ft = removeprefix(split[0], prefix=sep).strip()
            syntax = ft if ft.isalnum() else context.filetype
            return Doc(text=text, syntax=syntax)
        else:
            return doc
    else:
        return doc


def _clamp(hi: int) -> Callable[[int], int]:
    return lambda i: clamp(1, i, hi)


def _positions(
    display: PreviewDisplay,
    event: _Event,
    lines: Sequence[str],
    state: State,
) -> Iterator[Tuple[int, int, _Pos]]:
    scr_width, scr_height = state.screen
    top, btm, left, right = (
        event.row,
        event.row + event.height + 1,
        event.col,
        event.col + event.width + event.scrollbar,
    )
    dls = tuple(display_width(line, tabsize=state.context.tabstop) for line in lines)
    limit_w = _clamp(min(display.x_max_len, max(chain((0,), dls))))
    limit_h = _clamp(sum(ceil((dl or 1) / display.x_max_len) for dl in dls))

    ns_width = limit_w(scr_width - left)
    n_height = limit_h(top - 1)
    b_width, b_height = border_w_h(display.border)

    ns_col = left - 1
    n = _Pos(
        row=top - 1 - n_height - b_height,
        col=ns_col,
        height=n_height,
        width=ns_width,
    )
    if n.row > 1 and display.positions.north is not None:
        yield 1, display.positions.north, n

    s = _Pos(
        row=btm,
        col=ns_col,
        height=limit_h(scr_height - btm),
        width=ns_width,
    )

    if s.row + s.height < scr_height - 1 and display.positions.south is not None:
        yield 2, display.positions.south, s

    we_height = limit_h(scr_height - top - 2)
    w_width = limit_w(left - 2)

    w = _Pos(
        row=top,
        col=left - 2 - w_width - b_width,
        height=we_height,
        width=w_width,
    )

    if display.positions.west is not None:
        yield 3, display.positions.west, w

    e = _Pos(
        row=top,
        col=right + 1,
        height=we_height,
        width=limit_w(scr_width - right - 2),
    )

    if display.positions.east is not None:
        yield 4, display.positions.east, e


def _set_win(nvim: Nvim, display: PreviewDisplay, buf: Buffer, pos: _Pos) -> None:
    opts = {
        "relative": "editor",
        "anchor": "NW",
        "style": "minimal",
        "noautocmd": True,
        "width": pos.width,
        "height": pos.height,
        "row": pos.row,
        "col": pos.col,
        "border": display.border,
    }
    win: Window = nvim.api.open_win(buf, False, opts)
    win_set_option(nvim, win=win, key="wrap", val=True)
    win_set_var(nvim, win=win, key=_FLOAT_WIN_UUID, val=True)


@rpc(blocking=True, schedule=True)
def _go_show(
    nvim: Nvim,
    stack: Stack,
    preview_id: str,
    syntax: str,
    preview: Sequence[str],
    _pos: Mapping[str, int],
) -> None:
    if preview_id == state().preview_id.hex:
        pos = _Pos(**_pos)
        buf = create_buf(
            nvim, listed=False, scratch=True, wipe=True, nofile=True, noswap=True
        )
        buf_set_preview(nvim, buf=buf, syntax=syntax, preview=preview)
        _set_win(nvim, display=stack.settings.display.preview, buf=buf, pos=pos)


def _show_preview(
    nvim: Nvim, stack: Stack, event: _Event, doc: Doc, s: State, preview_id: UUID
) -> None:
    new_doc = _preprocess(s.context, doc=doc)
    text = expand_tabs(s.context, text=new_doc.text)
    lines = text.splitlines()
    pit = _positions(stack.settings.display.preview, event=event, lines=lines, state=s)

    def key(k: Tuple[int, int, _Pos]) -> Tuple[int, int, int, int]:
        idx, rank, pos = k
        return pos.height * pos.width, idx == s.pum_location, -rank, -idx

    ordered = sorted(pit, key=key, reverse=True)
    if ordered:
        (pum_location, _, pos), *__ = ordered
        state(pum_location=pum_location)
        nvim.api.exec_lua(
            f"{_go_show.name}(...)",
            (preview_id.hex, new_doc.syntax, lines, asdict(pos)),
        )


_TASK: Optional[Task] = None


def _resolve_comp(
    nvim: Nvim,
    stack: Stack,
    event: _Event,
    extern: Tuple[Extern, Union[CompletionItem, str]],
    maybe_doc: Optional[Doc],
    state: State,
) -> None:
    global _TASK
    prev = _TASK
    timeout = stack.settings.display.preview.resolve_timeout if maybe_doc else None
    en, item = extern

    async def cont() -> None:
        if prev:
            await cancel(prev)

        cached = stack.lru.get(state.preview_id)

        if cached:
            doc = cached.doc
        else:
            if en is Extern.lsp and isinstance(item, Mapping):
                done, _ = await wait((request(nvim, item=item),), timeout=timeout)
                comp = (await done.pop()) if done else None
                if comp:
                    stack.lru[state.preview_id] = comp
                doc = (comp.doc if comp else None) or maybe_doc
            elif en is Extern.path and isinstance(item, str):
                doc = await show(
                    cwd=state.cwd,
                    path=Path(item),
                    ellipsis=stack.settings.display.pum.ellipsis,
                    height=stack.settings.clients.paths.preview_lines,
                )
                if doc:
                    stack.lru[state.preview_id] = Completion(
                        source="",
                        weight_adjust=0,
                        label="",
                        sort_by="",
                        primary_edit=Edit(new_text=""),
                        doc=doc,
                        icon_match=None,
                    )
            else:
                doc = None

        if doc:
            await async_call(
                nvim,
                _show_preview,
                nvim,
                stack=stack,
                event=event,
                doc=doc,
                s=state,
                preview_id=state.preview_id,
            )

    _TASK = cast(Task, go(nvim, aw=cont()))


def _virt_text(nvim: Nvim, ghost: GhostText, text: str) -> None:
    if ghost.enabled:
        lhs, rhs = ghost.context
        overlay, *_ = text.splitlines() or ("",)
        virt_text = lhs + overlay + rhs

        ns = create_ns(nvim, ns=_NS)
        win = cur_win(nvim)
        buf = win_get_buf(nvim, win=win)
        row, col = win_get_cursor(nvim, win=win)
        mark = ExtMark(
            idx=1,
            begin=(row, 0),
            end=(row, 0),
            meta={
                "virt_text_pos": "overlay",
                "hl_mode": "blend",
                "virt_text_win_col": col,
                "virt_text": ((virt_text, ghost.highlight_group),),
            },
        )
        clear_ns(nvim, buf=buf, id=ns)
        buf_set_extmarks(nvim, buf=buf, id=ns, marks=(mark,))


_DECODER = new_decoder(_Event)


@rpc(blocking=True, schedule=True)
def _cmp_changed(nvim: Nvim, stack: Stack, event: Mapping[str, Any] = {}) -> None:
    _kill_win(nvim, stack=stack, reset=False)
    with timeit("PREVIEW"):
        try:
            ev: _Event = _DECODER(event)
        except DecodeError:
            pass
        else:
            data = ev.completed_item.user_data
            if data:
                s = state(preview_id=data.uid)
                if data.doc and data.doc.text:
                    _show_preview(
                        nvim,
                        stack=stack,
                        event=ev,
                        doc=data.doc,
                        s=s,
                        preview_id=s.preview_id,
                    )
                elif data.extern:
                    _resolve_comp(
                        nvim,
                        stack=stack,
                        event=ev,
                        extern=data.extern,
                        maybe_doc=data.doc,
                        state=s,
                    )
                _virt_text(
                    nvim,
                    ghost=stack.settings.display.ghost_text,
                    text=data.primary_edit.new_text,
                )


autocmd("CompleteChanged") << f"lua {_cmp_changed.name}(vim.v.event)"


@rpc(blocking=True, schedule=True)
def _bigger_preview(nvim: Nvim, stack: Stack, args: Tuple[str, Sequence[str]]) -> None:
    syntax, lines = args
    nvim.command("stopinsert")
    set_preview(nvim, syntax=syntax, preview=lines)


@rpc(blocking=True)
def preview_preview(nvim: Nvim, stack: Stack, *_: str) -> str:
    win = next(_ls(nvim), None)
    if win:
        buf = win_get_buf(nvim, win=win)
        syntax = buf_get_option(nvim, buf=buf, key="syntax")
        lines = buf_get_lines(nvim, buf=buf, lo=0, hi=-1)
        nvim.exec_lua(f"{_bigger_preview.name}(...)", (syntax, lines))

    escaped: str = nvim.api.replace_termcodes("<c-e>", True, False, True)
    return escaped
