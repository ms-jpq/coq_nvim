from collections import deque
from itertools import chain
from textwrap import dedent
from typing import Iterator, Sequence

from pynvim.api.common import NvimError
from pynvim.api.nvim import Buffer, Nvim
from pynvim.api.window import Window
from pynvim_pp.api import (
    ExtMark,
    ask,
    buf_del_extmarks,
    buf_get_extmarks,
    buf_get_lines,
    buf_linefeed,
    create_ns,
    cur_win,
    win_get_buf,
    win_set_cursor,
)
from pynvim_pp.lib import write
from pynvim_pp.logging import log
from pynvim_pp.operators import set_visual_selection

from ...lang import LANG
from ...registry import rpc
from ...shared.types import UTF8
from ...snippets.consts import MOD_PAD
from ..edit import EditInstruction, apply
from ..mark import NS
from ..rt_types import Stack
from ..state import state


def _ls_marks(nvim: Nvim, ns: int, buf: Buffer) -> Sequence[ExtMark]:
    ordered = sorted(
        buf_get_extmarks(nvim, id=ns, buf=buf),
        key=lambda m: (
            m.idx % MOD_PAD,
            m.begin,
            m.end,
        ),
    )
    return ordered


def _single_mark(
    nvim: Nvim,
    mark: ExtMark,
    marks: Sequence[ExtMark],
    ns: int,
    win: Window,
    buf: Buffer,
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
            win_set_cursor(nvim, win=win, row=r1, col=c1)
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
        buf_del_extmarks(nvim, buf=buf, id=ns, marks=(mark,))


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


def _linked_marks(
    nvim: Nvim,
    mark: ExtMark,
    linked: Sequence[ExtMark],
    ns: int,
    win: Window,
    buf: Buffer,
) -> bool:
    marks = tuple(chain((mark,), linked))

    def preview(mark: ExtMark) -> str:
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
        for p in map(preview, marks):
            if p:
                return p
        else:
            return ""

    resp = ask(nvim, question=LANG("expand marks"), default=place_holder())
    if resp is not None:
        nvim.options["undolevels"] = nvim.options["undolevels"]
        apply(nvim, buf=buf, instructions=_trans(resp, marks=marks))
        buf_del_extmarks(nvim, buf=buf, id=ns, marks=marks)
        row, col = mark.begin
        win_set_cursor(nvim, win=win, row=row, col=col)
        return True
    else:
        return False


@rpc(blocking=True)
def nav_mark(nvim: Nvim, stack: Stack) -> None:
    ns = create_ns(nvim, ns=NS)
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    marks = deque(_ls_marks(nvim, ns=ns, buf=buf))

    if marks:
        mark = marks.popleft()
        base_idx = mark.idx % MOD_PAD
        linked = tuple(m for m in marks if m.idx % MOD_PAD == base_idx)

        def single() -> None:
            _single_mark(nvim, mark=mark, marks=marks, ns=ns, win=win, buf=buf)

        if not linked:
            single()
        else:
            edited = _linked_marks(
                nvim, mark=mark, linked=linked, ns=ns, win=win, buf=buf
            )
            if not edited:
                single()

    else:
        msg = LANG("no more marks")
        write(nvim, msg)
