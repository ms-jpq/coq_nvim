from hashlib import sha256
from json import dumps
from typing import Any

from std2.tree import recur_sort

from ..consts import LSP_ARTIFACTS, SNIPPET_ART_HASH, SNIPPET_ARTIFACTS, SNIPPET_HASH
from .load import load_parsable
from .lsp import lsp


def _json(o: Any) -> str:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    return json


def main() -> None:
    snippets = load_parsable()
    lsprotocol = lsp()

    j_lsp = _json(lsprotocol)
    LSP_ARTIFACTS.write_text(j_lsp)

    j_snippets = _json(snippets)
    bj_snippets = j_snippets.encode()
    hashed = sha256(bj_snippets).digest()

    SNIPPET_HASH.write_bytes(hashed)
    SNIPPET_ART_HASH.write_bytes(hashed)
    SNIPPET_ARTIFACTS.write_bytes(bj_snippets)

