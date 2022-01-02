from asyncio import run
from os import linesep
from shutil import get_terminal_size
from sys import stderr
from typing import Iterator
from unittest import TestCase

from ...coq.ci.load import load
from ...coq.shared.context import EMPTY_CONTEXT
from ...coq.shared.types import SnippetEdit
from ...coq.snippets.parse import parse_norm
from ...coq.snippets.parsers.types import ParseError, ParseInfo

_THRESHOLD = 0.95


def _edits() -> Iterator[SnippetEdit]:
    loaded = run(load())
    for snip in loaded.snippets.values():
        edit = SnippetEdit(new_text=snip.content, grammar=snip.grammar)
        yield edit


class Parser(TestCase):
    def test_1(self) -> None:
        edits = tuple(_edits())

        def errs() -> Iterator[Exception]:
            for edit in edits:
                try:
                    parse_norm(
                        set(),
                        smart=True,
                        context=EMPTY_CONTEXT,
                        snippet=edit,
                        info=ParseInfo(visual="", clipboard="", comment_str=("", "")),
                    )
                except ParseError as e:
                    yield e

        errors = tuple(errs())
        succ = 1 - (len(errors) / len(edits) if edits else 0)
        self.assertGreater(succ, _THRESHOLD)

        cols, _ = get_terminal_size()
        sep = "=" * cols + linesep
        print(*errors, sep=sep, file=stderr)
