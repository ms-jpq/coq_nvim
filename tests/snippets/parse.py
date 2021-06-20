from sys import stderr
from typing import Iterator
from unittest import TestCase

from ...coq.ci.load import load
from ...coq.shared.types import SnippetEdit
from ...coq.snippets.main import EMPTY_CTX, EMPTY_ENV
from ...coq.snippets.parse import parse

_THRESHOLD = 0.95


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
                    parse(EMPTY_CTX, env=EMPTY_ENV, snippet=edit)
                except Exception as e:
                    yield e

        errors = tuple(errs())
        succ = 1 - (len(errors) / len(edits) if edits else 0)
        self.assertGreater(succ, _THRESHOLD)

        for err in errors:
            print(err, file=stderr)

