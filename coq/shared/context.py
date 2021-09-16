from os.path import normcase
from pathlib import Path, PurePath
from typing import AbstractSet
from uuid import uuid4

from .parse import is_word
from .parse import lower as _lower
from .types import Context

_FILE = Path(__file__).resolve()

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
    scr_col=0,
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
)


def cword(
    unifying_chars: AbstractSet[str], lower: bool, context: Context, sort_by: str
) -> str:
    char = sort_by[:1]
    trans = _lower if lower else lambda c: c
    if char.isspace():
        return context.ws_before
    elif is_word(char, unifying_chars=unifying_chars):
        return trans(context.words_before)
    else:
        return trans(context.syms_before)


def cword_after(
    unifying_chars: AbstractSet[str], lower: bool, context: Context, sort_by: str
) -> str:
    char = sort_by[-1:]
    trans = _lower if lower else lambda c: c
    if char.isspace():
        return context.ws_after
    elif is_word(char, unifying_chars=unifying_chars):
        return trans(context.words_after)
    else:
        return ""
