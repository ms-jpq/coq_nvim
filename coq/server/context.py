from typing import AbstractSet, Literal, Tuple, cast
from uuid import uuid4

from pynvim import Nvim
from pynvim_pp.api import LFfmt
from pynvim_pp.atomic import Atomic
from pynvim_pp.text_object import gen_split

from ..shared.types import Context
from .model.buffers.database import BDB


def context(
    nvim: Nvim,
    db: BDB,
    unifying_chars: AbstractSet[str],
) -> Context:

    with Atomic() as (atomic, ns):
        ns.cwd = atomic.call_function("getcwd", ())
        ns.name = atomic.buf_get_name(0)
        ns.filetype = atomic.buf_get_option(0, "filetype")
        ns.commentstring = atomic.buf_get_option(0, "commentstring")
        ns.changedtick = atomic.buf_get_var(0, "changedtick")
        ns.fileformat = atomic.buf_get_option(0, "fileformat")
        ns.tabstop = atomic.buf_get_option(0, "tabstop")
        ns.expandtab = atomic.buf_get_option(0, "expandtab")
        ns.cursor = atomic.win_get_cursor(0)
        atomic.commit(nvim)

    cwd = cast(str, ns.cwd)
    filename = cast(str, ns.name)
    filetype = cast(str, ns.filetype)
    comment_str = cast(str, ns.commentstring)
    changedtick = ns.changedtick
    pos = (row, col) = cast(Tuple[int, int], ns.cursor)
    tabstop = ns.tabstop
    expandtab = cast(bool, ns.expandtab)
    linefeed = cast(Literal["\n", "\r", "\r\n"], LFfmt[cast(str, ns.fileformat)])

    lines = db.lines(filename)
    line = lines[row]
    lhs, _, rhs = comment_str.partition("%s")
    b_line = line.encode()
    before, after = b_line[:col].decode(), b_line[col:].decode()
    split = gen_split(lhs=before, rhs=after, unifying_chars=unifying_chars)

    ctx = Context(
        uid=uuid4(),
        cwd=cwd,
        changedtick=changedtick,
        filename=filename,
        filetype=filetype,
        linefeed=linefeed,
        tabstop=tabstop,
        expandtab=expandtab,
        comment=(lhs, rhs),
        position=pos,
        line=split.lhs + split.rhs,
        line_before=split.lhs,
        line_after=split.rhs,
        lines=lines,
        lines_before=lines[:row],
        lines_after=lines[row + 1 :],
        words=split.word_lhs + split.word_rhs,
        words_before=split.word_lhs,
        words_after=split.word_rhs,
        syms=split.syms_lhs + split.syms_rhs,
        syms_before=split.syms_lhs,
        syms_after=split.syms_rhs,
    )
    return ctx

