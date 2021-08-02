from hashlib import sha256
from json import dumps
from pathlib import Path
from typing import Any

from std2.asyncio.subprocess import call
from std2.tree import recur_sort

from ..consts import (
    LSP_ARTIFACTS,
    SNIP_VARS,
    SNIPPET_ARTIFACTS,
    SNIPPET_GIT_SHA,
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

    prev_desired = SNIPPET_HASH_DESIRED.read_text()
    SNIP_VARS.mkdir(parents=True, exist_ok=True)
    SNIPPET_HASH_ACTUAL.write_text(hashed)
    SNIPPET_HASH_DESIRED.write_text(hashed)
    SNIPPET_ARTIFACTS.write_bytes(bj_snippets)

    if prev_desired != hashed:
        proc = await call(
            "git",
            "rev-parse",
            "--show-toplevel",
            cwd=SNIP_VARS,
            capture_stderr=False,
        )
        snip_git = Path(proc.out.decode().strip())
        if snip_git == SNIP_VARS:
            proc = await call(
                "git",
                "rev-parse",
                "HEAD",
                cwd=SNIP_VARS,
                capture_stderr=False,
            )
            SNIPPET_GIT_SHA.write_bytes(proc.out.strip())
        else:
            assert False
