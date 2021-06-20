from typing import Iterator
from unittest import TestCase
from uuid import uuid4

from ...coq.ci.load import load
from ...coq.shared.types import Context, EditEnv, SnippetEdit
from ...coq.snippets.parse import parse

_THRESHOLD = 0.95


_CTX = Context(
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
_ENV = EditEnv(
    linefeed="\n",
    tabstop=2,
    expandtab=True,
)


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
                    parse(_CTX, env=_ENV, snippet=edit)
                except Exception as e:
                    yield e

        errors = tuple(errs())
        succ = len(errors) / len(edits) if edits else 0

        if succ < _THRESHOLD:
            for err in errors:
                raise err

