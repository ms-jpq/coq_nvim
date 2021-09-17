from asyncio.tasks import gather
from difflib import unified_diff

from ..consts import DEBUG, LSP_ARTIFACTS, VARS
from ..server.registrants.snippets import BUNDLED_PATH_TPL, jsonify
from ..snippets.types import SCHEMA
from .load import load_parsable
from .lsp import lsp


async def main() -> None:
    lsprotocol, snippets = await gather(lsp(), load_parsable())
    j_lsp, j_snippets = jsonify(lsprotocol), jsonify(snippets)

    LSP_ARTIFACTS.write_text(j_lsp, encoding="UTF-8")
    snip_art = VARS / "snippets" / BUNDLED_PATH_TPL.substitute(schema=SCHEMA)
    snip_art.parent.mkdir(parents=True, exist_ok=True)

    if DEBUG and snip_art.exists():
        for line in unified_diff(
            snip_art.read_text().splitlines(), j_snippets.splitlines()
        ):
            print(line)

    snip_art.write_text(j_snippets, encoding="UTF-8")
