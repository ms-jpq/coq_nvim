from difflib import unified_diff

from pynvim_pp.logging import log

from ..consts import DEBUG, VARS
from ..server.registrants.snippets import BUNDLED_PATH_TPL, jsonify
from ..shared.types import UTF8
from ..snippets.types import SCHEMA
from .load import load_parsable


async def main() -> None:
    snippets = await load_parsable()
    j_snippets = jsonify(snippets)

    snip_art = VARS / "snippets" / BUNDLED_PATH_TPL.substitute(schema=SCHEMA)
    snip_art.parent.mkdir(parents=True, exist_ok=True)

    if DEBUG and snip_art.exists():
        for line in unified_diff(
            snip_art.read_text().splitlines(), j_snippets.splitlines()
        ):
            log.debug("%s", line)

    snip_art.write_text(j_snippets, encoding=UTF8)
