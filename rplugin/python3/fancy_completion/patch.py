from itertools import chain
from os import linesep
from typing import Any, Dict, Iterator, List, Optional, Sequence, Tuple, cast

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.window import Window

from .types import Edit, Payload, Position


def calculate_edit(payload: Payload) -> Tuple[Edit, Edit]:
    row, col = payload.position.row, payload.position.col
    old_prefix, new_prefix = payload.old_prefix, payload.new_prefix
    old_suffix, new_suffix = payload.old_suffix, payload.new_suffix

    p0, p1, lhs, = old_prefix.rpartition(linesep)
    rhs, s0, s1 = old_suffix.partition(linesep)

    b_row = row - p0.count(linesep) - p1.count(linesep)
    b_col = col - len(lhs)
    e_row = row + s0.count(linesep) + s1.count(linesep)
    e_col = col + len(rhs) - 1

    l_edit = Edit(
        begin=Position(row=b_row, col=b_col),
        end=Position(row=row, col=col),
        new_text=new_prefix,
    )
    r_edit = Edit(
        begin=Position(row=row, col=col),
        end=Position(row=e_row, col=e_col),
        new_text=new_suffix,
    )
    return l_edit, r_edit


def is_vaild(edit: Edit) -> bool:
    begin, end = edit.begin, edit.end
    if begin.row == end.row:
        return begin.col <= end.col
    else:
        return begin.row < end.row


def overlap(lhs: Edit, rhs: Edit) -> bool:
    l_rows = {*range(lhs.begin.row, lhs.end.row + 1)}
    r_rows = {*range(rhs.begin.row, rhs.end.row + 1)}
    overlap = l_rows & r_rows
    if overlap:
        if len(overlap) == 1:
            if lhs.begin.row in overlap and rhs.begin.row in overlap:
                l_cols = {*range(lhs.begin.col, lhs.end.col + 1)}
                r_cols = {*range(rhs.begin.col, rhs.end.col + 1)}
                return len(l_cols & r_cols) > 0
            elif lhs.end.row in overlap and rhs.begin.row in overlap:
                return lhs.end.col >= rhs.begin.col
            elif rhs.end.row in overlap and lhs.begin.row in overlap:
                return rhs.end.col >= lhs.begin.col
            else:
                assert False
        else:
            return True
    else:
        return False


def rank(edit: Edit) -> Tuple[int, int]:
    return edit.begin.row, edit.begin.col


def consolidate_edits(payload: Payload) -> Sequence[Edit]:
    main = calculate_edit(payload)
    edits = chain(main, payload.edits)

    def cont() -> Iterator[Edit]:
        seen: List[Edit] = []
        for edit in edits:
            if is_vaild(edit) and not any(overlap(edit, prev) for prev in seen):
                seen.append(edit)
                yield edit

    return sorted(cont(), key=rank)


def calc_index(edits: Sequence[Edit]) -> Tuple[int, int]:
    top_idx = min(e.begin.row for e in edits) + 1
    btm_idx = max(e.end.row for e in edits)
    return top_idx, btm_idx


def within_edit(pos: Position, edit: Optional[Edit]) -> bool:
    if edit:
        row, col = pos.row, pos.col
        b_row, b_col = edit.begin.row, edit.begin.col
        e_row, e_col = edit.end.row, edit.end.col

        if row == b_row and row == e_row:
            return col >= b_col and col <= e_col
        elif row == b_row:
            return col >= b_col
        elif row == e_row:
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
    if edits:
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
