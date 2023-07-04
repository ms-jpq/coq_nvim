from os.path import normcase
from typing import Optional, Tuple, cast

from pynvim_pp.atomic import Atomic
from pynvim_pp.buffer import Buffer, linefeed
from pynvim_pp.lib import decode, encode
from pynvim_pp.text_object import gen_split
from pynvim_pp.types import NoneType

from ..shared.parse import lower
from ..shared.settings import MatchOptions
from ..shared.types import UTF16, UTF32, ChangeEvent, Context
from .state import State


async def context(
    options: MatchOptions, state: State, change: Optional[ChangeEvent], manual: bool
) -> Context:
    with Atomic() as (atomic, ns):
        ns.scr_col = atomic.call_function("screencol", ())
        ns.win_height = atomic.win_get_height(0)
        ns.buf = atomic.get_current_buf()
        ns.name = atomic.buf_get_name(0)
        ns.line_count = atomic.buf_line_count(0)
        ns.filetype = atomic.buf_get_option(0, "filetype")
        ns.commentstring = atomic.buf_get_option(0, "commentstring")
        ns.fileformat = atomic.buf_get_option(0, "fileformat")
        ns.tabstop = atomic.buf_get_option(0, "tabstop")
        ns.expandtab = atomic.buf_get_option(0, "expandtab")
        ns.cursor = atomic.win_get_cursor(0)
        await atomic.commit(NoneType)

    scr_col = ns.scr_col(int)
    win_size = ns.win_height(int) // 2
    buf = ns.buf(Buffer)
    (r, col) = cast(Tuple[int, int], ns.cursor(NoneType))
    row = r - 1
    pos = (row, col)
    buf_line_count = ns.line_count(int)
    filename = normcase(ns.name(str))
    filetype = ns.filetype(str)
    comment_str = ns.commentstring(str)
    tabstop = ns.tabstop(int)
    expandtab = ns.expandtab(bool)
    linesep = linefeed(ns.fileformat(str))

    lo = max(0, row - win_size)
    hi = min(buf_line_count, row + win_size + 1)
    lines = await buf.get_lines(lo=lo, hi=hi)

    r = row - lo
    line = lines[r]
    lines_before, lines_after = lines[:r], lines[r + 1 :]

    lhs, _, rhs = comment_str.partition("%s")
    b_line = encode(line)
    line_before, line_after = decode(b_line[:col]), decode(b_line[col:])
    utf16_col = len(encode(line_before, encoding=UTF16)) // 2
    utf32_col = len(encode(line_before, encoding=UTF32)) // 4

    split = gen_split(
        lhs=line_before, rhs=line_after, unifying_chars=options.unifying_chars
    )
    l_words_before, l_words_after = lower(split.word_lhs), lower(split.word_rhs)
    l_syms_before, l_syms_after = lower(split.syms_lhs), lower(split.syms_rhs)
    is_lower = l_words_before + l_words_after == split.word_lhs + split.word_rhs

    ctx = Context(
        manual=manual,
        change_id=state.change_id,
        commit_id=state.commit_id,
        cwd=state.cwd,
        buf_id=buf.number,
        filename=filename,
        filetype=filetype,
        line_count=buf_line_count,
        linefeed=linesep,
        tabstop=tabstop,
        expandtab=expandtab,
        comment=(lhs, rhs),
        position=pos,
        cursor=(row, col, utf16_col, utf32_col),
        scr_col=scr_col,
        win_size=win_size,
        line=split.lhs + split.rhs,
        line_before=line_before,
        line_after=line_after,
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
        l_words_before=l_words_before,
        l_words_after=l_words_after,
        l_syms_before=l_syms_before,
        l_syms_after=l_syms_after,
        is_lower=is_lower,
        change=change,
    )
    return ctx
