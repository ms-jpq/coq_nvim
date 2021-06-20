from operator import add, sub
from typing import Iterator, Sequence, Tuple, TypedDict

from pynvim.api.nvim import Nvim, Window
from pynvim_pp.api import cur_win, win_get_buf, win_get_cursor, win_set_cursor
from pynvim_pp.keymap import Keymap

from ...consts import NS
from ...registry import rpc
from ...shared.settings import KeyMapping
from ...shared.types import Mark
from ..runtime import Stack


class _MarkDetail(TypedDict):
    end_row: int
    end_col: int


def _ls_marks(nvim: Nvim, win: Window) -> Sequence[Mark]:
    buf = win_get_buf(nvim, win=win)
    ns = nvim.api.create_namespace(NS)
    marks: Sequence[Tuple[int, int, int, _MarkDetail]] = nvim.api.buf_get_extmarks(
        buf, ns, 0, -1, {"details": True}
    )

    def cont() -> Iterator[Mark]:
        for idx, r1, c1, details in marks:
            r2, c2 = details["end_row"], details["end_col"]
            m = Mark(idx=idx, begin=(r1, c1), end=(r2, c2))
            yield m

    ordered = sorted(cont(), key=lambda m: (m.begin, m.end))
    return ordered


def _rank(row: int, col: int, idx_mark: Tuple[int, Mark]) -> Tuple[int, int, int, int]:
    _, mark = idx_mark
    (r1, c1), (r2, c2) = mark.begin, mark.end
    return abs(row - r1), abs(row - r2), abs(col - c1), abs(col - c2)


@rpc(blocking=True)
def _nav_mark(nvim: Nvim, stack: Stack, inc: bool) -> None:
    win = cur_win(nvim)
    marks = _ls_marks(nvim, win=win)
    row, col = win_get_cursor(nvim, win=win)
    ranked = iter(sorted(enumerate(marks), key=lambda im: _rank(row, col, im)))
    closest = next(ranked, None)
    if closest:
        idx, _ = closest
        op = add if inc else sub
        new_idx = op(idx, 1) % len(marks)
        mark = marks[new_idx]

        (r1, c1), (r2, c2) = mark.begin, mark.end
        win_set_cursor(nvim, win=win, row=r2, col=c2 - 1)
        nvim.command(f"norm! v")
        win_set_cursor(nvim, win=win, row=r1, col=c1)

        print(f"Mark {idx + 1} of {len(marks)}", flush=True)
    else:
        print("NOTHING", flush=True)


def set_km(nvim: Nvim, mapping: KeyMapping) -> None:
    keymap = Keymap()
    keymap.n(mapping.prev_mark) << f"<cmd>lua {_nav_mark.name}(false)<cr>"
    keymap.n(mapping.next_mark) << f"<cmd>lua {_nav_mark.name}(true)<cr>"
    keymap.v(mapping.prev_mark) << f"<esc><cmd>lua {_nav_mark.name}(false)<cr>"
    keymap.v(mapping.next_mark) << f"<esc><cmd>lua {_nav_mark.name}(true)<cr>"

    keymap.drain(buf=None).commit(nvim)

