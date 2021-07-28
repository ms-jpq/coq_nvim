from argparse import ArgumentParser, Namespace
from sys import stdin

from ..shared.context import EMPTY_CONTEXT
from ..shared.types import SnippetEdit
from .parse import parse


def _parse_args() -> Namespace:
    parser = ArgumentParser()
    parser.add_argument("grammar", choices=("lsp", "snu"))
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    edit = SnippetEdit(grammar=args.grammar, new_text=stdin.read())
    parsed = parse(set(), context=EMPTY_CONTEXT, snippet=edit, sort_by="", visual="")
    print(parsed)
