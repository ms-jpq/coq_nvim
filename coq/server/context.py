from typing import AbstractSet, Optional

from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.api import buf_filetype, buf_name, cur_win, win_get_buf, win_get_cursor
from pynvim_pp.text_object import gen_split

from ..shared.types import Context
from .model.database import Database


def context(
    nvim: Nvim,
    db: Database,
    unifying_chars: AbstractSet[str],
    buf: Optional[Buffer],
    filename: Optional[str],
    filetype: Optional[str],
) -> Context:
    win = cur_win(nvim)
    buf = buf or win_get_buf(nvim, win=win)
    row, col = win_get_cursor(nvim, win=win)
    pos = (row, col)

    line, *_ = db.lines(buf=buf.number, lo=row, hi=row + 1)
    filename = filename if filename is not None else buf_name(nvim, buf=buf)
    filetype = filetype if filetype is not None else buf_filetype(nvim, buf=buf)

    b_line = line.encode()
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
