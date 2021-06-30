from os import linesep
from shutil import get_terminal_size
from sys import stderr
from typing import Iterator
from unittest import TestCase

from ...coq.ci.load import load
from ...coq.shared.types import SnippetEdit
from ...coq.snippets.main import EMPTY_CTX
from ...coq.snippets.parse import parse
from ...coq.snippets.parsers.types import ParseError

_THRESHOLD = 0.85


def _edits() -> Iterator[SnippetEdit]:
    specs = load()
    for snippets in specs.snippets.values():
        for snippet in snippets:
            edit = SnippetEdit(
                new_text=snippet.content,
                grammar=snippet.grammar,
            )
            yield edit


class Parser(TestCase):
    def test_1(self) -> None:
        edits = tuple(_edits())

        def errs() -> Iterator[Exception]:
            for edit in edits:
                try:
                    parse(EMPTY_CTX, snippet=edit, sort_by="")
                except ParseError as e:
                    yield e

        errors = tuple(errs())
        succ = 1 - (len(errors) / len(edits) if edits else 0)
        self.assertGreater(succ, _THRESHOLD)

        cols, _ = get_terminal_size()
        sep = "=" * cols + linesep
        print(*errors, sep=sep, file=stderr)

