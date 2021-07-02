from pathlib import Path
from uuid import uuid4

from .types import Context

EMPTY_CONTEXT = Context(
    uid=uuid4(),
    pum_visible=False,
    changedtick=0,
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

