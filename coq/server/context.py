from typing import AbstractSet

from pynvim import Nvim
from pynvim_pp.api import (
    buf_filetype,
    buf_get_lines,
    buf_name,
    cur_win,
    win_get_buf,
    win_get_cursor,
)
from pynvim_pp.text_object import SplitCtx, gen_split

from ..agnostic.datatypes import Context, NvimPos


def gen_context_at(
    nvim: Nvim, pos: NvimPos, unifying_chars: AbstractSet[str]
) -> SplitCtx:
    row, col = pos
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)

    lines = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
    b_line = next(iter(lines)).encode()
    before, after = b_line[:col].decode(), b_line[col:].decode()
    split = gen_split(lhs=before, rhs=after, unifying_chars=unifying_chars)

    return split


def gen_context(nvim: Nvim,  unifying_chars: AbstractSet[str]) -> Context:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    row, col = win_get_cursor(nvim, win=win)
    pos = (row, col)

    lines = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
    filename = buf_name(nvim, buf=buf)
    filetype = buf_filetype(nvim, buf=buf)

    b_line = next(iter(lines)).encode()
    before, after = b_line[:col].decode(), b_line[col:].decode()
    split = gen_split(lhs=before, rhs=after, unifying_chars=unifying_chars)

    ctx = Context(
        filename=filename,
        filetype=filetype,
        position=pos,
        line=split.lhs + split.rhs,
        line_before=split.lhs,
        line_after=split.rhs,
        words=split.word_lhs + split.word_rhs,
        words_before=split.word_lhs,
        words_after=split.word_rhs,
        syms=split.syms_lhs + split.syms_rhs,
        syms_before=split.syms_lhs,
        syms_after=split.syms_rhs,
    )
    return ctx


def should_complete(context: Context) -> bool:
    return context.line_before != "" and not context.line_before.isspace()
