from pathlib import Path
from typing import AbstractSet, Optional

from pynvim import Nvim
from pynvim_pp.api import (
    buf_filetype,
    buf_get_lines,
    buf_name,
    cur_win,
    win_get_buf,
    win_get_cursor,
)
from pynvim_pp.text_object import gen_split

from ...shared.parse import normalize
from ...shared.protocol.types import Context, Position


def gen_context(
    nvim: Nvim, project: Path, unifying_chars: AbstractSet[str], pos: Optional[Position]
) -> Context:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    position = pos if pos else win_get_cursor(nvim, win=win)
    row, col = position

    lines = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
    filename = buf_name(nvim, buf=buf)
    filetype = buf_filetype(nvim, buf=buf)

    b_line = next(iter(lines)).encode()
    before, after = normalize(b_line[:col].decode()), normalize(b_line[col:].decode())
    line = before + after
    split = gen_split(lhs=before, rhs=after, unifying_chars=unifying_chars)

    ctx = Context(
        project=str(project),
        filename=filename,
        filetype=filetype,
        position=position,
        line=line,
        line_before=before,
        line_after=after,
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
