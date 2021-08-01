from hashlib import sha256
from json import dumps
from typing import Any

from std2.tree import recur_sort

from ..consts import (
    LSP_ARTIFACTS,
    SNIPPET_ARTIFACTS,
    SNIPPET_HASH_ACTUAL,
    SNIPPET_HASH_DESIRED,
)
from .load import load_parsable
from .lsp import lsp


def _json(o: Any) -> str:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    return json


async def main() -> None:
    snippets = await load_parsable()
    lsprotocol = await lsp()

    j_lsp = _json(lsprotocol)
    LSP_ARTIFACTS.write_text(j_lsp)

    j_snippets = _json(snippets)
    bj_snippets = j_snippets.encode()
    hashed = sha256(bj_snippets).hexdigest()

    SNIPPET_HASH_ACTUAL.write_text(hashed)
    SNIPPET_HASH_DESIRED.write_text(hashed)
    SNIPPET_ARTIFACTS.write_bytes(bj_snippets)
