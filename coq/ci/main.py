from json import dumps
from pathlib import Path
from typing import Any

from std2.tree import recur_sort

from ..consts import LSP_ARTIFACTS, SNIPPET_ARTIFACTS
from .load import load_parsable
from .lsp import lsp


def _dump(path: Path, o: Any) -> None:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    path.write_text(json)


def main() -> None:
    snippets = load_parsable()
    lsprotocol = lsp()
    _dump(SNIPPET_ARTIFACTS, o=snippets)
    _dump(LSP_ARTIFACTS, o=lsprotocol)

