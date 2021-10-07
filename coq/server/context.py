from difflib import unified_diff
from itertools import takewhile
from os import linesep
from os.path import normcase
from typing import Literal, Tuple, cast

from pynvim import Nvim
from pynvim.api import Buffer
from pynvim_pp.api import LFfmt, buf_get_lines
from pynvim_pp.atomic import Atomic
from pynvim_pp.lib import decode, encode
from pynvim_pp.text_object import gen_split

from ..consts import DEBUG
from ..databases.buffers.database import BDB
from ..shared.settings import MatchOptions
from ..shared.types import Context
from .state import State


def context(
    nvim: Nvim, db: BDB, options: MatchOptions, state: State, manual: bool
) -> Context:
    with Atomic() as (atomic, ns):
        ns.scr_col = atomic.call_function("screencol", ())
        ns.pumwidth = atomic.get_option("pumwidth")
        ns.buf = atomic.get_current_buf()
        ns.name = atomic.buf_get_name(0)
        ns.line_count = atomic.buf_line_count(0)
        ns.filetype = atomic.buf_get_option(0, "filetype")
        ns.commentstring = atomic.buf_get_option(0, "commentstring")
        ns.fileformat = atomic.buf_get_option(0, "fileformat")
        ns.tabstop = atomic.buf_get_option(0, "tabstop")
        ns.expandtab = atomic.buf_get_option(0, "expandtab")
        ns.cursor = atomic.win_get_cursor(0)
        atomic.commit(nvim)

    scr_col = ns.scr_col
    pumwidth = ns.pumwidth
    buf = cast(Buffer, ns.buf)
    (r, col) = cast(Tuple[int, int], ns.cursor)
    row = r - 1
    pos = (row, col)
    buf_line_count = ns.line_count
    filename = normcase(cast(str, ns.name))
    filetype = cast(str, ns.filetype)
    comment_str = cast(str, ns.commentstring)
    tabstop = ns.tabstop
    expandtab = cast(bool, ns.expandtab)
    linefeed = cast(Literal["\n", "\r", "\r\n"], LFfmt[cast(str, ns.fileformat)].value)

    lo = max(0, row - options.proximate_lines)
    hi = min(buf_line_count, row + options.proximate_lines + 1)
    lines = buf_get_lines(nvim, buf=buf, lo=lo, hi=hi)
    if DEBUG:
        db_line_count, db_lit = db.lines(buf.number, lo=lo, hi=hi)
        db_lines = tuple(db_lit)
        assert db_line_count in {
            buf_line_count - 1,
            buf_line_count,
            buf_line_count + 1,
        }, (db_line_count, buf_line_count)
        assert tuple(
            "" if idx == row else line for idx, line in enumerate(db_lines, start=lo)
        ) == tuple(
            "" if idx == row else line for idx, line in enumerate(lines, start=lo)
        ), linesep.join(
            unified_diff(lines, db_lines)
        )

    r = row - lo
    line = lines[r]
    lines_before, lines_after = lines[:r], lines[r + 1 :]

    lhs, _, rhs = comment_str.partition("%s")
    b_line = encode(line)
    before, after = decode(b_line[:col]), decode(b_line[col:])
    split = gen_split(lhs=before, rhs=after, unifying_chars=options.unifying_chars)

    ctx = Context(
        manual=manual,
        change_id=state.change_id,
        commit_id=state.commit_id,
        cwd=state.cwd,
        buf_id=buf.number,
        filename=filename,
        filetype=filetype,
        line_count=buf_line_count,
        linefeed=linefeed,
        tabstop=tabstop,
        expandtab=expandtab,
        comment=(lhs, rhs),
        position=pos,
        pumwidth=pumwidth,
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
        ws_before=split.ws_lhs,
        ws_after=split.ws_rhs,
    )
    return ctx
