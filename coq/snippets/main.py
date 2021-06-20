from argparse import ArgumentParser, Namespace
from sys import stdin
from uuid import uuid4

from ..shared.types import Context, EditEnv, SnippetEdit
from .parse import parse

EMPTY_CTX = Context(
    uid=uuid4(),
    cwd="",
    filename="",
    filetype="",
    position=(0, 0),
    line="",
    line_before="",
    line_after="",
    words="",
    words_before="",
    words_after="",
    syms="",
    syms_before="",
    syms_after="",
)

EMPTY_ENV = EditEnv(
    linefeed="\n",
    tabstop=2,
    expandtab=True,
)


def _parse_args() -> Namespace:
    parser = ArgumentParser()
    parser.add_argument("grammar", choices=("lsp", "snu"))
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    edit = SnippetEdit(grammar=args.grammar, new_text=stdin.read())
    parsed = parse(EMPTY_CTX, env=EMPTY_ENV, snippet=edit)
    print(parsed)

