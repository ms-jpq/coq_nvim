from pathlib import Path
from pprint import pformat
from sys import stderr
from typing import Literal, Optional, Tuple, cast
from uuid import UUID

from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.api import LFfmt
from pynvim_pp.atomic import Atomic
from pynvim_pp.text_object import gen_split

from ..shared.settings import Options
from ..shared.types import Context
from .databases.buffers.database import BDB


def context(
    nvim: Nvim, options: Options, db: BDB, commit_id: UUID, change_id: UUID
) -> Optional[Context]:

    with Atomic() as (atomic, ns):
        ns.scr_col = atomic.call_function("screencol", ())
        ns.cwd = atomic.call_function("getcwd", ())
        ns.buf = atomic.get_current_buf()
        ns.name = atomic.buf_get_name(0)
        ns.filetype = atomic.buf_get_option(0, "filetype")
        ns.commentstring = atomic.buf_get_option(0, "commentstring")
        ns.fileformat = atomic.buf_get_option(0, "fileformat")
        ns.tabstop = atomic.buf_get_option(0, "tabstop")
        ns.expandtab = atomic.buf_get_option(0, "expandtab")
        ns.cursor = atomic.win_get_cursor(0)
        atomic.commit(nvim)

    scr_col = ns.scr_col
    cwd = cast(str, ns.cwd)
    buf_nr = cast(Buffer, ns.buf).number
    (r, col) = cast(Tuple[int, int], ns.cursor)
    row = r - 1
    pos = (row, col)
    filename = cast(str, ns.name)
    filetype = cast(str, ns.filetype)
    comment_str = cast(str, ns.commentstring)
    tabstop = ns.tabstop
    expandtab = cast(bool, ns.expandtab)
    linefeed = cast(Literal["\n", "\r", "\r\n"], LFfmt[cast(str, ns.fileformat)].value)

    line_count, lines = db.lines(
        buf_nr, lo=row - options.context_lines, hi=row + options.context_lines + 1
    )
    r = min(options.context_lines, row)
    if r >= len(lines):
        print(pformat(tuple(enumerate(lines))), file=stderr, flush=True)
        return None
    else:
        line = lines[r]
        lines_before, lines_after = lines[:r], lines[r + 1 :]

        lhs, _, rhs = comment_str.partition("%s")
        b_line = line.encode()
        before, after = b_line[:col].decode(), b_line[col:].decode()
        split = gen_split(lhs=before, rhs=after, unifying_chars=options.unifying_chars)

        ctx = Context(
            change_id=change_id,
            commit_id=commit_id,
            cwd=Path(cwd),
            buf_id=buf_nr,
            filename=filename,
            filetype=filetype,
            line_count=line_count,
            linefeed=linefeed,
            tabstop=tabstop,
            expandtab=expandtab,
            comment=(lhs, rhs),
            position=pos,
            scr_col=scr_col,
            line=split.lhs + split.rhs,
            line_before=split.lhs,
            line_after=split.rhs,
            lines=lines,
            lines_before=lines_before,
            lines_after=lines_after,
            words=split.word_lhs + split.word_rhs,
            words_before=split.word_lhs,
            words_after=split.word_rhs,
            syms=split.syms_lhs + split.syms_rhs,
            syms_before=split.syms_lhs,
            syms_after=split.syms_rhs,
        )
        return ctx

