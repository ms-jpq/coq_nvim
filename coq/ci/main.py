from asyncio.tasks import gather
from json import dumps
from typing import Any

from std2.graphlib import recur_sort

from ..consts import LSP_ARTIFACTS, VARS
from ..server.registrants.snippets import BUNDLED_PATH_TPL
from ..snippets.types import SCHEMA
from .load import load_parsable
from .lsp import lsp


def _json(o: Any) -> str:
    json = dumps(recur_sort(o), check_circular=False, ensure_ascii=False, indent=2)
    return json


async def main() -> None:
    lsprotocol, snippets = await gather(lsp(), load_parsable())

    j_lsp = _json(lsprotocol)
    LSP_ARTIFACTS.write_text(j_lsp)

    j_snippets = _json(snippets)
    bj_snippets = j_snippets.encode()

    snip_art = VARS / "snippets" / BUNDLED_PATH_TPL.substitute(schema=SCHEMA)
    snip_art.parent.mkdir(parents=True, exist_ok=True)
    snip_art.write_bytes(bj_snippets)
