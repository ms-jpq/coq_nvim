from asyncio.tasks import gather
from json import dumps
from typing import Any

from std2.graphlib import recur_sort

from ..consts import LSP_ARTIFACTS, VARS
from .load import load_parsable
from .lsp import lsp

_SNIPPET_ARTIFACTS = VARS / "snippets" / "coq+snippets+v2.json"


def _json(o: Any) -> str:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    return json


async def main() -> None:
    lsprotocol, snippets = await gather(lsp(), load_parsable())

    j_lsp = _json(lsprotocol)
    LSP_ARTIFACTS.write_text(j_lsp)

    j_snippets = _json(snippets)
    bj_snippets = j_snippets.encode()

    _SNIPPET_ARTIFACTS.parent.mkdir(parents=True, exist_ok=True)
    _SNIPPET_ARTIFACTS.write_bytes(bj_snippets)
