from asyncio.tasks import gather

from ..consts import LSP_ARTIFACTS, VARS
from ..server.registrants.snippets import BUNDLED_PATH_TPL, jsonify
from ..snippets.types import SCHEMA
from .load import load_parsable
from .lsp import lsp


async def main() -> None:
    lsprotocol, snippets = await gather(lsp(), load_parsable())

    j_lsp = jsonify(lsprotocol)
    LSP_ARTIFACTS.write_text(j_lsp)

    j_snippets = jsonify(snippets)
    bj_snippets = j_snippets.encode()

    snip_art = VARS / "snippets" / BUNDLED_PATH_TPL.substitute(schema=SCHEMA)
    snip_art.parent.mkdir(parents=True, exist_ok=True)
    snip_art.write_bytes(bj_snippets)
