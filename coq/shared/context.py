from pathlib import Path
from uuid import uuid4

from .types import Context

EMPTY_CONTEXT = Context(
    change_id=uuid4(),
    commit_id=uuid4(),
    cwd=Path(),
    buf_id=0,
    filename="",
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

