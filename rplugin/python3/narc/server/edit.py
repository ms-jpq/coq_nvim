from dataclasses import dataclass
from itertools import chain, count
from os import linesep
from typing import Dict, Iterator, List, Optional, Sequence, Tuple, Union, cast

from pynvim import Nvim
from pynvim.api.buffer import Buffer
from pynvim.api.window import Window

from ..shared.logging import log
from ..shared.parse import normalize
from ..shared.types import LEdit, MEdit, Position, SEdit
from .parse import parse_common_affix
from .types import MatchOptions, Payload

IText = Union[str, Tuple[()]]
TextStream = Sequence[IText]


@dataclass(frozen=True)
class Replacement:
    begin: int
    length: int
    text: TextStream


def gen_medit(
    nvim: Nvim,
    buf: Buffer,
    position: Position,
    sedit: Optional[SEdit],
    options: MatchOptions,
) -> Optional[MEdit]:
    row, col = position.row, position.col
    if sedit:
        match = sedit.new_text
        line, *_ = nvim.api.buf_get_lines(buf, row, row + 1, True)
        line_before, line_after = line[:col], line[col:]
        match_normalized = normalize(match)
        old_prefix, old_suffix = parse_common_affix(
            before=line_before,
            after=line_after,
            match_normalized=match_normalized,
            unifying_chars=options.unifying_chars,
        )
        medit = MEdit(
            old_prefix=old_prefix,
            new_prefix=match,
            old_suffix=old_suffix,
            new_suffix="",
        )
        return medit
    else:
        return None


# 0 based
def rows_to_fetch(
    position: Position, medit: Optional[MEdit], ledits: Sequence[LEdit]
) -> Optional[Tuple[int, int]]:
    def cont() -> Iterator[Tuple[int, int]]:
        row = position.row
        if medit:
            old_lc, new_lc = (
                medit.old_prefix.count(linesep),
                medit.old_suffix.count(linesep),
            )
            main_btm, main_top = row - old_lc, row + new_lc
            yield main_btm, main_top
            for edit in ledits:
                yield edit.begin.row, edit.end.row

    indices = tuple(cont())
    if indices:
        btms, tops = zip(*indices)
        btm_idx, top_idx = min(btms), max(tops)
        return btm_idx, top_idx
    else:
        return None


def row_lengths(rows: Sequence[str], start: int) -> Dict[int, int]:
    ret = {idx: len(row) + 1 for idx, row in enumerate(rows, start)}
    return ret


def calculate_replacement(
    row_lens: Dict[int, int], start: int, edit: LEdit
) -> Replacement:
    b_row, e_row = edit.begin.row, edit.end.row
    b_col, e_col = edit.begin.col, edit.end.col

    begin = sum(row_lens[r] for r in range(start, b_row)) + b_col

    def r_len() -> int:
        if b_row == e_row:
            return e_col - b_col
        else:
            lo = (row_lens[b_row] - 1) - b_col
            mi = sum(row_lens[r] for r in range(b_row + 1, e_row))
            hi = e_col
            return lo + mi + hi

    length = r_len()

    text = tuple(edit.new_text)
    replacement = Replacement(begin=begin, length=length, text=text)
    return replacement


def calculate_main_replacement(
    row_lens: Dict[int, int], start: int, medit: Optional[MEdit], position: Position
) -> Optional[Replacement]:
    if medit:
        row, col = position.row, position.col

        len_pre = len(medit.old_prefix)
        begin = sum(row_lens[r] for r in range(start, row)) + col - len_pre
        length = len_pre + len(medit.old_suffix)
        text = (*medit.new_prefix, (), *medit.new_suffix)

        replacement = Replacement(begin=begin, length=length, text=text)
        return replacement
    else:
        return None


def overlap(r1: Replacement, r2: Replacement) -> bool:
    r1_end, r2_end = r1.begin + r1.length, r2.begin + r2.length
    return bool(range(max(r1.begin, r2.begin), min(r1_end, r2_end) + 1))


def rank(replacement: Replacement) -> Tuple[int, int, TextStream]:
    return replacement.begin, replacement.length, replacement.text


def consolidate_replacements(
    row_lens: Dict[int, int],
    start: int,
    position: Position,
    medit: Optional[MEdit],
    ledits: Sequence[LEdit],
) -> Sequence[Replacement]:
    main = calculate_main_replacement(
        row_lens, start=start, position=position, medit=medit
    )
    main_replacements = (main,) if main else ()
    auxiliary_replacements = (
        calculate_replacement(row_lens, start=start, edit=edit) for edit in ledits
    )

    def cont() -> Iterator[Replacement]:
        seen: List[Replacement] = []
        for r in chain(main_replacements, sorted(auxiliary_replacements, key=rank)):
            if not any(overlap(r, s) for s in seen):
                seen.append(r)
                yield r

    return sorted(cont(), key=rank)


def stream_lines(rows: Sequence[str]) -> Iterator[Tuple[int, str]]:
    it = count()
    for row in rows:
        for char in row:
            yield next(it), char
        yield next(it), linesep


def perform_edits(
    stream: Iterator[Tuple[int, str]], replacements: Iterator[Replacement]
) -> Iterator[IText]:
    replacement = next(replacements, None)
    for idx, char in stream:
        if replacement and idx == replacement.begin:
            yield from iter(replacement.text)
            if replacement.length:
                for _ in range(replacement.length - 1):
                    next(stream, None)
            else:
                yield char
            replacement = next(replacements, None)
        else:
            yield char


def split_stream(
    stream: Iterator[Union[str, Tuple[()]]], start: int
) -> Tuple[Sequence[str], Optional[Position]]:
    position: Optional[Position] = None

    def cont() -> Iterator[str]:
        nonlocal position
        curr: List[str] = []
        r_it, c_it = count(start), count()
        r, c = next(r_it), next(c_it)

        for char in stream:
            if char == ():
                position = Position(row=r, col=c)
            elif char == linesep:
                yield "".join(curr)
                curr.clear()
                r = next(r_it)
                c_it = count()
                c = 0
            else:
                c = next(c_it)
                curr.append(cast(str, char))
        if curr:
            yield "".join(curr)

    return tuple(cont()), position


def replace_lines(nvim: Nvim, payload: Payload, options: MatchOptions) -> None:
    win: Window = nvim.api.get_current_win()
    buf: Buffer = nvim.api.get_current_buf()

    position, ledits = payload.position, payload.ledits
    medit = payload.medit or gen_medit(
        nvim, buf=buf, position=position, sedit=payload.sedit, options=options
    )
    index = rows_to_fetch(position, medit=medit, ledits=ledits)
    if index:
        btm_idx, top_idx = index
        top_idx = top_idx + 1

        old_lines: Sequence[str] = nvim.api.buf_get_lines(buf, btm_idx, top_idx, True)

        row_lens = row_lengths(old_lines, start=btm_idx)
        replacements = consolidate_replacements(
            row_lens, start=btm_idx, position=position, medit=medit, ledits=ledits
        )
        stream = stream_lines(old_lines)
        text_stream = perform_edits(stream, replacements=iter(replacements))
        new_lines, pos = split_stream(text_stream, start=btm_idx)

        nvim.api.buf_set_lines(buf, btm_idx, top_idx, True, new_lines)
        if pos:
            nvim.api.win_set_cursor(win, (pos.row + 1, pos.col))
        else:
            log.warn("%s", "No cursor position found")

        log.debug("%s", replacements)
    else:
        log.warn("%s", "No edits found")

    log.debug("%s", payload)
