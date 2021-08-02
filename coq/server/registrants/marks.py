from collections import deque
from itertools import chain
from textwrap import dedent
from typing import Iterator, Sequence, Tuple, TypedDict
from uuid import uuid4

from pynvim.api.common import NvimError
from pynvim.api.nvim import Buffer, Nvim
from pynvim.api.window import Window
from pynvim_pp.api import (
    ask,
    buf_get_lines,
    buf_linefeed,
    cur_win,
    win_get_buf,
    win_set_cursor,
)
from pynvim_pp.lib import write
from pynvim_pp.logging import log
from pynvim_pp.operators import set_visual_selection

from ...lang import LANG
from ...registry import rpc
from ...shared.types import UTF8, Mark, RangeEdit
from ...snippets.consts import LINKED_PAD
from ..edit import edit
from ..mark import NS
from ..nvim.completions import UserData
from ..rt_types import Stack
from ..state import state


class _MarkDetail(TypedDict):
    end_row: int
    end_col: int


def _ls_marks(nvim: Nvim, ns: str, buf: Buffer) -> Sequence[Mark]:
    marks: Sequence[Tuple[int, int, int, _MarkDetail]] = nvim.api.buf_get_extmarks(
        buf, ns, 0, -1, {"details": True}
    )

    def cont() -> Iterator[Mark]:
        for idx, r1, c1, details in marks:
            r2, c2 = details["end_row"], details["end_col"]
            m = Mark(idx=idx, begin=(r1, c1), end=(r2, c2), text="")
            yield m

    ordered = sorted(
        cont(),
        key=lambda m: (
            m.idx - LINKED_PAD if m.idx > LINKED_PAD else m.idx,
            m.begin,
            m.end,
        ),
    )
    return ordered


def _single_mark(
    nvim: Nvim, mark: Mark, marks: Sequence[Mark], ns: int, win: Window, buf: Buffer
) -> None:
    (r1, c1), (r2, c2) = mark.begin, mark.end
    try:
        if r1 == r2 and abs(c2 - c1) == 0:
            row, col = r1, min(c1, c2)
            win_set_cursor(nvim, win=win, row=row, col=col)
        else:
            row, col = r1, c1
            set_visual_selection(
                nvim, win=win, mode="v", mark1=(r1, c1), mark2=(r2, c2 - 1)
            )
            nvim.command("norm! c")
    except NvimError as e:
        msg = f"""
        bad mark location {mark}

        {e}
        """
        log.warn("%s", dedent(msg))
    else:
        nvim.command("startinsert")
        state(inserted=(row, col))
        msg = LANG("applied mark", marks_left=len(marks))
        write(nvim, msg)
    finally:
        nvim.api.buf_del_extmark(buf, ns, mark.idx)


def _trans(new_text: str, mark: Mark, marks: Sequence[Mark]) -> UserData:
    def one(mark: Mark) -> RangeEdit:
        edit = RangeEdit(
            new_text=new_text,
            begin=mark.begin,
            end=mark.end,
            encoding=UTF8,
        )
        return edit

    primary_edit, *secondary_edits = map(one, chain((mark,), marks))
    data = UserData(
        uid=uuid4(),
        instance=uuid4(),
        sort_by="",
        change_uid=uuid4(),
        primary_edit=primary_edit,
        secondary_edits=secondary_edits,
        doc=None,
        extern=None,
    )
    return data


def _linked_marks(
    nvim: Nvim, mark: Mark, marks: Sequence[Mark], stack: Stack, ns: int, buf: Buffer
) -> None:
    ms = tuple(chain((mark,), marks))

    def preview(mark: Mark) -> str:
        linesep = buf_linefeed(nvim, buf=buf)
        (r1, c1), (r2, c2) = mark.begin, mark.end
        lo, hi = min(r1, r2), max(r1, r2) + 1
        lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)

        def cont() -> Iterator[str]:
            for idx, line in enumerate(lines, start=lo):
                if idx == r1 and idx == r2:
                    yield line.encode(UTF8)[c1:c2].decode(UTF8)
                elif idx == r1:
                    yield line.encode(UTF8)[c1:].decode(UTF8)
                elif idx == r2:
                    yield line.encode(UTF8)[:c2].decode(UTF8)
                else:
                    yield line

        return linesep.join(cont())

    def place_holder() -> str:
        for p in map(preview, ms):
            if p:
                return p
        else:
            return ""

    try:
        resp = ask(nvim, question=LANG("expand marks"), default=place_holder())
        if resp is not None:
            data = _trans(resp, mark=mark, marks=marks)
            edit(nvim, stack=stack, state=state(), data=data, synthetic=True)

    except NvimError as e:
        msg = f"""
        bad mark locations {ms}

        {e}
        """
        log.warn("%s", dedent(msg))
    finally:
        for mark in ms:
            nvim.api.buf_del_extmark(buf, ns, mark.idx)


@rpc(blocking=True)
def nav_mark(nvim: Nvim, stack: Stack) -> None:
    ns = nvim.api.create_namespace(NS)
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    marks = deque(_ls_marks(nvim, ns=ns, buf=buf))

    if marks:
        mark = marks.popleft()
        if mark.idx <= LINKED_PAD:
            _single_mark(nvim, mark=mark, marks=marks, ns=ns, win=win, buf=buf)
        else:
            _linked_marks(nvim, mark=mark, marks=marks, ns=ns, stack=stack, buf=buf)

    else:
        msg = LANG("no more marks")
        write(nvim, msg)
