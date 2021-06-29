from argparse import ArgumentParser, Namespace
from pathlib import Path
from sys import stdin
from uuid import uuid4

from ..shared.types import Context, SnippetEdit
from .parse import parse

EMPTY_CTX = Context(
    uid=uuid4(),
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


def _parse_args() -> Namespace:
    parser = ArgumentParser()
    parser.add_argument("grammar", choices=("lsp", "snu"))
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    edit = SnippetEdit(grammar=args.grammar, new_text=stdin.read())
    parsed = parse(EMPTY_CTX, snippet=edit, sort_by="")
    print(parsed)

