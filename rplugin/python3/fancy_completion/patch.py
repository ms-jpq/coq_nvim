from dataclasses import dataclass
from itertools import chain, count
from os import linesep
from typing import Any, Dict, Iterator, List, Optional, Sequence, Tuple, cast

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.window import Window

from .types import Edit, Payload, Position


@dataclass(frozen=True)
class Replacement:
    begin: int
    length: int
    cursor: bool = False


def rows_to_fetch(payload: Payload) -> Tuple[int, int]:
    row = payload.position.row
    edits = payload.edits
    old_lc, new_lc = (
        payload.old_prefix.count(linesep),
        payload.old_suffix.count(linesep),
    )
    main_btm, main_top = row - old_lc, row + new_lc
    btm_idx = min(main_btm, *(e.begin.row for e in edits))
    top_idx = max(main_top, *(e.end.row for e in edits))
    return btm_idx, top_idx


def row_lengths(rows: Sequence[str], start: int) -> Dict[int, int]:
    ret = {idx: len(row) + 1 for idx, row in enumerate(rows, start)}
    return ret


def calculate_replacement(
    row_lens: Dict[int, int], start: int, edit: Edit
) -> Replacement:
    b_row, e_row = edit.begin.row, edit.end.row
    b_col, e_col = edit.begin.col, edit.end.col

    lower = sum(row_lens[r] for r in range(start, b_row)) + b_col
    begin = row_lens[b_row] - b_col - 1
    middle = sum(row_lens[r] for r in range(b_row + 1, e_row))
    end = e_col
    length = begin + middle + end

    replacement = Replacement(begin=lower, length=length)
    return replacement


def calculate_main_replacements(
    row_lens: Dict[int, int], start: int, payload: Payload
) -> Tuple[Replacement, Replacement]:
    row, col = payload.position.row, payload.position.col

    begin1 = sum(row_lens[r] for r in range(start, row)) + col
    length1 = len(payload.old_prefix)
    begin2 = begin1 + length1
    length2 = len(payload.old_suffix)

    replacement1 = Replacement(begin=begin1, length=length1)
    replacement2 = Replacement(begin=begin2, length=length2, cursor=True)
    return replacement1, replacement2


def consolidate_replacements(
    row_lens: Dict[int, int], start: int, payload: Payload
) -> Sequence[Replacement]:
    main_replacements = calculate_main_replacements(
        row_lens, start=start, payload=payload
    )
    auxiliary_replacements = (
        calculate_replacement(row_lens, start=start, edit=edit)
        for edit in payload.edits
    )
    return (*main_replacements, *auxiliary_replacements)


def stream_lines(rows: Sequence[str]) -> Iterator[Tuple[int, str]]:
    it = count()
    for row in rows:
        for char in row:
            yield next(it), char
        yield next(it), linesep


def perform_edits(
    stream: Iterator[Tuple[int, str]], replacements: Iterator[Replacement]
) -> Iterator[str]:
    for idx, char in stream:
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
    btm_idx, top_idx = rows_to_fetch(payload)
    win: Window = nvim.api.get_current_win()
    buf: Buffer = nvim.api.get_current_buf()
    old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)

    row_lens = row_lengths(old_lines, start=btm_idx)
    # stream = perform_edits(rows, edits=iter(edits))
    # new_lines = split_stream(stream)

    # nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
    # nvim.api.win_set_cursor(win, (new_row, new_col))

    nvim.api.out_write(str(payload) + "\n")
    nvim.api.out_write(str(old_lines) + "\n")


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
