from itertools import chain
from os import linesep
from typing import Any, Dict, Iterator, List, Optional, Sequence, Tuple, cast

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.window import Window

from .types import Edit, Payload, Position


def calculate_edit(payload: Payload) -> Edit:
    row, col = payload.position.row, payload.position.col
    old_prefix, new_prefix = payload.old_prefix, payload.new_prefix
    old_suffix, new_suffix = payload.old_suffix, payload.new_suffix

    p0, p1, lhs, = old_prefix.rpartition(linesep)
    rhs, s0, s1 = old_suffix.partition(linesep)

    b_row = row - p0.count(linesep) - p1.count(linesep)
    b_col = col - len(lhs)
    e_row = row + s0.count(linesep) + s1.count(linesep)
    e_col = col + len(rhs)

    edit = Edit(
        begin=Position(row=b_row, col=b_col),
        end=Position(row=e_row, col=e_col),
        new_text=new_prefix + new_suffix,
    )
    return edit


def consolidate_edits(payload: Payload) -> Sequence[Edit]:
    main_edit = calculate_edit(payload)
    edits = (*payload.edits, main_edit)

    def rank(edit: Edit) -> Tuple[int, int]:
        return edit.begin.row, edit.begin.col

    ranked = sorted(edits, key=rank)

    def cont() -> Iterator[Edit]:
        p_row, p_col = -1, -1
        for edit in ranked:
            b_row, b_col = edit.begin.row, edit.begin.col
            e_row, e_col = edit.end.row, edit.end.col
            if b_row >= p_row and b_col >= p_col and e_row >= b_row and e_col >= b_col:
                p_row, p_col = e_row, e_col
                yield edit

    return tuple(cont())


def calc_index(edits: Sequence[Edit]) -> Tuple[int, int]:
    top_idx = min(e.begin.row for e in edits) + 1
    btm_idx = max(e.end.row for e in edits)
    return top_idx, btm_idx


def within_edit(pos: Position, edit: Optional[Edit]) -> bool:
    if edit:
        row, col = pos.row, pos.col
        b_row, b_col = edit.begin.row, edit.begin.col
        e_row, e_col = edit.end.row, edit.end.col

        if row == b_row:
            return col >= b_col
        elif row == edit.end.row:
            return col <= e_col
        else:
            return row > b_row and row < e_row
    else:
        return False


def rows_stream(rows: Sequence[str], starting: int) -> Iterator[Tuple[Position, str]]:
    for r, row in enumerate(rows, starting):
        for c, char in enumerate(row):
            yield Position(row=r, col=c), char
    yield Position(row=-1, col=-1), linesep


def perform_edits(
    stream: Iterator[Tuple[Position, str]], edits: Iterator[Edit]
) -> Iterator[str]:
    edit = next(edits, None)
    for pos, char in stream:
        if within_edit(pos, edit):
            yield from iter(edit.new_text)
            for pos, char in stream:
                if within_edit(pos, edit):
                    pass
                else:
                    new_stream = chain(((pos, char),), stream)
                    yield from perform_edits(new_stream, edits)
                    break
            break
        else:
            yield char


def split_stream(stream: Iterator[str]) -> Sequence[str]:
    def cont() -> Iterator[str]:
        curr: List[str] = []
        for char in stream:
            if char == linesep:
                yield "".join(curr)
                curr.clear()
            else:
                curr.append(char)
        if curr:
            yield "".join(curr)

    return tuple(cont())


def replace_lines(nvim: Nvim, payload: Payload) -> None:
    edits = consolidate_edits(payload)
    top_idx, btm_idx = calc_index(edits)

    win: Window = nvim.api.get_current_win()
    buf: Buffer = nvim.api.get_current_buf()
    old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)

    rows = rows_stream(old_lines, starting=btm_idx)
    stream = perform_edits(rows, edits=iter(edits))
    new_lines = split_stream(stream)

    nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
    # nvim.api.win_set_cursor(win, (new_row, new_col))

    nvim.api.out_write(str(payload) + "\n")
    nvim.api.out_write(str(edits) + "\n")

    # nvim.api.out_write(str(new_lines) + "\n")


def apply_patch(nvim: Nvim, comp: Dict[str, Any]) -> None:
    data = comp.get("user_data")
    d = cast(dict, data)
    try:
        position = Position(**d["position"])
        edits = tuple(
            Edit(
                begin=Position(row=edit["begin"]["row"], col=edit["begin"]["col"]),
                end=Position(row=edit["end"]["row"], col=edit["end"]["col"]),
                new_text=edit["new_text"],
            )
            for edit in d["edits"]
        )
        payload = Payload(**{**d, **dict(position=position, edits=edits)})
    except (KeyError, TypeError):
        pass
    else:
        replace_lines(nvim, payload=payload)
