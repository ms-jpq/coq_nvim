from collections import deque
from textwrap import dedent
from typing import AbstractSet, Iterator, Sequence, Tuple, TypedDict
from uuid import uuid4

from pynvim.api.common import NvimError
from pynvim.api.nvim import Buffer, Nvim
from pynvim.api.window import Window
from pynvim_pp.api import cur_win, win_get_buf, win_set_cursor
from pynvim_pp.lib import write
from pynvim_pp.logging import log
from pynvim_pp.operators import set_visual_selection

from ...lang import LANG
from ...registry import rpc
from ...shared.settings import Settings
from ...shared.types import Mark
from ...snippets.consts import LINKED_PAD
from ..rt_types import Stack
from ..state import state

_NS = uuid4().hex


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

    return sorted(
        cont(), key=lambda m: m.idx - LINKED_PAD if m.idx > LINKED_PAD else m.idx
    )


def _single_mark(
    nvim: Nvim, mark: Mark, marks: Sequence[Mark], ns: int, win: Window, buf: Buffer
) -> None:
    try:
        (r1, c1), (r2, c2) = mark.begin, mark.end
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


def _linked_marks(
    nvim: Nvim, marks: AbstractSet[Mark], ns: int, win: Window, buf: Buffer
) -> None:
    pass


@rpc(blocking=True)
def nav_mark(nvim: Nvim, stack: Stack) -> None:
    ns = nvim.api.create_namespace(_NS)
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    marks = deque(_ls_marks(nvim, ns=ns, buf=buf))

    if marks:
        mark = marks.popleft()
        if mark.idx <= LINKED_PAD:
            _single_mark(nvim, mark=mark, marks=marks, ns=ns, win=win, buf=buf)
        else:
            _linked_marks(nvim, marks=set(), ns=ns, win=win, buf=buf)

    else:
        msg = LANG("no more marks")
        write(nvim, msg)


def mark(nvim: Nvim, settings: Settings, buf: Buffer, marks: Sequence[Mark]) -> None:
    mks = tuple(mark for mark in marks if mark.idx and mark.text)

    ns = nvim.api.create_namespace(_NS)
    nvim.api.buf_clear_namespace(buf, ns, 0, -1)
    for mark in mks:
        (r1, c1), (r2, c2) = mark.begin, mark.end
        opts = {
            "id": mark.idx + 1,
            "end_line": r2,
            "end_col": c2,
            "hl_group": settings.display.mark_highlight_group,
        }
        try:
            nvim.api.buf_set_extmark(buf, ns, r1, c1, opts)
        except NvimError:
            log.warn("%s", f"bad mark location {mark}")

    msg = LANG("added marks", regions=" ".join(f"[{mark.text}]" for mark in mks))
    write(nvim, msg)
