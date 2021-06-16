from typing import AbstractSet, Optional
from uuid import uuid4

from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.api import (
    buf_filetype,
    buf_get_lines,
    buf_get_option,
    buf_linefeed,
    buf_name,
    cur_win,
    win_get_buf,
    win_get_cursor,
)
from pynvim_pp.text_object import gen_split

from ..shared.types import Context, EditEnv


def context(
    nvim: Nvim,
    unifying_chars: AbstractSet[str],
    cwd: str,
) -> Context:
    win = cur_win(nvim)
    buf = win_get_buf(nvim, win=win)
    row, col = win_get_cursor(nvim, win=win)
    pos = (row, col)

    line, *_ = buf_get_lines(nvim, buf=buf, lo=row, hi=row + 1)
    filename = buf_name(nvim, buf=buf)
    filetype = buf_filetype(nvim, buf=buf)

    b_line = line.encode()
    before, after = b_line[:col].decode(), b_line[col:].decode()
    split = gen_split(lhs=before, rhs=after, unifying_chars=unifying_chars)

    ctx = Context(
        uid=uuid4(),
        cwd=cwd,
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


def should_complete(prev: Optional[Context], cur: Context) -> bool:
    return (not prev or prev and cur.position != prev.position)  and (cur.line_before != "" and not cur.line_before.isspace())


def edit_env(nvim: Nvim, buf: Buffer) -> EditEnv:
    env = EditEnv(
        linefeed=buf_linefeed(nvim, buf=buf),
        tabstop=buf_get_option(nvim, buf=buf, key="tabstop"),
        expandtab=buf_get_option(nvim, buf=buf, key="expandtab"),
    )
    return env

