from os.path import normcase
from pathlib import Path, PurePath
from typing import AbstractSet
from uuid import uuid4

from pynvim_pp.text_object import is_word

from .types import Context

_FILE = Path(__file__).resolve(strict=True)

EMPTY_CONTEXT = Context(
    manual=True,
    change_id=uuid4(),
    commit_id=uuid4(),
    cwd=PurePath(),
    buf_id=0,
    filename=normcase(_FILE),
    filetype="",
    line_count=0,
    linefeed="\n",
    tabstop=2,
    expandtab=True,
    comment=("", ""),
    position=(0, 0),
    cursor=(0, 0, 0, 0),
    scr_col=0,
    win_size=0,
    line="",
    line_before="",
    line_after="",
    lines=(),
    lines_before=(),
    lines_after=(),
    words="",
    words_before="",
    words_after="",
    syms="",
    syms_before="",
    syms_after="",
    ws_before="",
    ws_after="",
    l_words_before="",
    l_words_after="",
    l_syms_before="",
    l_syms_after="",
    is_lower=True,
    change=None,
)


def cword_before(
    unifying_chars: AbstractSet[str], lower: bool, context: Context, sort_by: str
) -> str:
    char = sort_by[:1]

    if char.isspace():
        return context.ws_before
    elif is_word(unifying_chars, chr=char):
        return context.l_words_before if lower else context.words_before
    else:
        return context.l_syms_before if lower else context.syms_before


def cword_after(
    unifying_chars: AbstractSet[str], lower: bool, context: Context, sort_by: str
) -> str:
    char = sort_by[-1:]

    if char.isspace():
        return context.ws_after
    elif is_word(unifying_chars, chr=char):
        return context.l_words_after if lower else context.words_after
    else:
        return context.l_syms_after if lower else context.syms_after
