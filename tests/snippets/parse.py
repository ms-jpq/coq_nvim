from asyncio import run
from os import linesep
from shutil import get_terminal_size
from sys import stderr
from typing import Iterator
from unittest import TestCase

from ...coq.ci.load import load
from ...coq.shared.types import SnippetEdit
from ...coq.snippets.main import EMPTY_CONTEXT
from ...coq.snippets.parse import parse
from ...coq.snippets.parsers.types import ParseError

_THRESHOLD = 0.95


def _edits() -> Iterator[SnippetEdit]:
    specs = run(load())
    for _, (_, snippets) in specs.items():
        for _, snips in snippets.items():
            for snip in snips:
                edit = SnippetEdit(
                    new_text=snip.content,
                    grammar=snip.grammar,
                )
                yield edit


class Parser(TestCase):
    def test_1(self) -> None:
        edits = tuple(_edits())

        def errs() -> Iterator[Exception]:
            for edit in edits:
                try:
                    parse(
                        set(),
                        context=EMPTY_CONTEXT,
                        snippet=edit,
                        visual="",
                    )
                except ParseError as e:
                    yield e

        errors = tuple(errs())
        succ = 1 - (len(errors) / len(edits) if edits else 0)
        self.assertGreater(succ, _THRESHOLD)

        cols, _ = get_terminal_size()
        sep = "=" * cols + linesep
        print(*errors, sep=sep, file=stderr)
