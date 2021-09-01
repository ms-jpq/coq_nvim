from os.path import normcase
from pathlib import Path, PurePath
from uuid import uuid4

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
)
