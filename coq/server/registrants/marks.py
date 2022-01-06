from collections import deque
from dataclasses import replace
from itertools import chain
from json import dumps
from textwrap import dedent
from typing import Iterable, Iterator, Sequence
from uuid import uuid4

from pynvim.api.common import NvimError
from pynvim.api.nvim import Buffer, Nvim
from pynvim.api.window import Window
from pynvim_pp.api import (
    ExtMark,
    ask,
    buf_del_extmarks,
    buf_get_extmarks,
    create_ns,
    cur_win,
    extmarks_text,
    win_get_buf,
    win_get_cursor,
    win_set_cursor,
)
from pynvim_pp.lib import write
from pynvim_pp.logging import log

from ...lang import LANG
from ...registry import rpc
from ...snippets.parsers.parser import decode_mark_idx
from ..edit import EditInstruction, apply
from ..mark import NS
from ..rt_types import Stack
from ..state import state

_OG_IDX = str(uuid4())


def _ls_marks(nvim: Nvim, ns: int, buf: Buffer) -> Sequence[ExtMark]:
    ordered = sorted(
        (
            replace(
                mark,
                idx=decode_mark_idx(mark.idx) - 1,
                meta={**mark.meta, _OG_IDX: mark.idx},
            )
            for mark in buf_get_extmarks(nvim, id=ns, buf=buf)
            if mark.end >= mark.begin
        ),
        key=lambda m: (m.idx == 0, m.idx, m.begin, m.end),
    )

    return ordered


def _del_marks(nvim: Nvim, buf: Buffer, id: int, marks: Iterable[ExtMark]) -> None:
    it = (replace(mark, idx=mark.meta[_OG_IDX]) for mark in marks)
    buf_del_extmarks(nvim, buf=buf, id=id, marks=it)


def _marks(nvim: Nvim, ns: int, win: Window, buf: Buffer) -> Iterator[ExtMark]:
    cursor = win_get_cursor(nvim, win=win)
    for mark in _ls_marks(nvim, ns=ns, buf=buf):
        if mark.begin == cursor and mark.end == cursor:
            _del_marks(nvim, buf=buf, id=ns, marks=(mark,))
        else:
            yield mark


def _trans(new_text: str, marks: Sequence[ExtMark]) -> Iterator[EditInstruction]:
    new_lines = new_text.splitlines()
    for mark in marks:
        yield EditInstruction(
            primary=False,
            begin=mark.begin,
            end=mark.end,
            cursor_yoffset=0,
            cursor_xpos=-1,
            new_lines=new_lines,
        )


def _single_mark(
    nvim: Nvim,
    mark: ExtMark,
    marks: Sequence[ExtMark],
    ns: int,
    win: Window,
    buf: Buffer,
) -> None:
    row, col = mark.begin
    nvim.options["undolevels"] = nvim.options["undolevels"]

    try:
        apply(nvim, buf=buf, instructions=_trans("", marks=(mark,)))
        win_set_cursor(nvim, win=win, row=row, col=col)
        nvim.command("startinsert")
    except NvimError as e:
        msg = f"""
        bad mark location {mark}

        {e}
        """
        log.warn("%s", dedent(msg))
    else:
        nvim.command("startinsert")
        state(inserted_pos=(row, col))
        msg = LANG("applied mark", marks_left=len(marks))
        write(nvim, msg)
    finally:
        _del_marks(nvim, buf=buf, id=ns, marks=(mark,))


def _linked_marks(
    nvim: Nvim,
    mark: ExtMark,
    linked: Sequence[ExtMark],
    ns: int,
    win: Window,
    buf: Buffer,
) -> bool:
    marks = tuple(chain((mark,), linked))
    place_holders = tuple(text for _, text in extmarks_text(nvim, buf=buf, marks=marks))
    texts = dumps(place_holders, check_circular=False, ensure_ascii=False)
    resp = ask(nvim, question=LANG("expand marks", texts=texts), default="")
    if resp is not None:
        row, col = mark.begin
        nvim.options["undolevels"] = nvim.options["undolevels"]
        apply(nvim, buf=buf, instructions=_trans(resp, marks=marks))
        _del_marks(nvim, buf=buf, id=ns, marks=marks)
        win_set_cursor(nvim, win=win, row=row, col=col)
        nvim.command("startinsert")
        state(inserted_pos=(row, col - 1))
        return True
    else:
        return False


@rpc(blocking=True)
def nav_mark(nvim: Nvim, stack: Stack) -> None:
    ns = create_ns(nvim, ns=NS)
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)

    if marks := deque(_marks(nvim, ns=ns, win=win, buf=buf)):
        mark = marks.popleft()

        def single() -> None:
            _single_mark(nvim, mark=mark, marks=marks, ns=ns, win=win, buf=buf)

        if linked := tuple(m for m in marks if m.idx == mark.idx):
            edited = _linked_marks(
                nvim, mark=mark, linked=linked, ns=ns, win=win, buf=buf
            )
            if not edited:
                single()
        else:
            single()

    else:
        msg = LANG("no more marks")
        write(nvim, msg)
