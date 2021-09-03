from asyncio import Semaphore, gather
from contextlib import suppress
from multiprocessing import cpu_count
from pathlib import Path
from typing import Any, Iterator, Tuple
from urllib.parse import urlparse
from uuid import UUID

from std2.asyncio.subprocess import call
from std2.pickle import new_decoder, new_encoder
from std2.tree import recur_sort
from yaml import safe_load

from ..consts import COMPILATION_YML, TMP_DIR
from ..shared.context import EMPTY_CONTEXT
from ..shared.types import SnippetEdit
from ..snippets.loaders.load import LoadedSnips
from ..snippets.loaders.load import load as load_from_paths
from ..snippets.parse import parse
from ..snippets.parsers.parser import ParseError
from ..snippets.types import ParsedSnippet
from .types import Compilation


def _p_name(uri: str) -> Path:
    return TMP_DIR / Path(urlparse(uri).path).name


async def _git_pull(sem: Semaphore, uri: str) -> None:
    async with sem:
        location = _p_name(uri)
        if location.is_dir():
            await call(
                "git",
                "pull",
                "--recurse-submodules",
                cwd=location,
                capture_stdout=False,
                capture_stderr=False,
            )
        else:
            await call(
                "git",
                "clone",
                "--depth=1",
                "--recurse-submodules",
                "--shallow-submodules",
                uri,
                str(location),
                cwd=TMP_DIR,
                capture_stdout=False,
                capture_stderr=False,
            )


async def load() -> LoadedSnips:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    yaml = safe_load(COMPILATION_YML.read_bytes())
    specs: Compilation = new_decoder(Compilation)(yaml)

    sem = Semaphore(value=cpu_count())
    await gather(*(_git_pull(sem, uri=uri) for uri in specs.git))

    parsed = load_from_paths(
        lsp=(TMP_DIR / path for path in specs.paths.lsp),
        neosnippet=(TMP_DIR / path for path in specs.paths.neosnippet),
        ultisnip=(TMP_DIR / path for path in specs.paths.ultisnip),
    )
    return parsed


async def load_parsable() -> Any:
    loaded = await load()

    def cont() -> Iterator[Tuple[UUID, ParsedSnippet]]:
        for uid, snip in loaded.snippets.items():
            edit = SnippetEdit(
                new_text=snip.content,
                grammar=snip.grammar,
            )
            with suppress(ParseError):
                parse(
                    set(),
                    context=EMPTY_CONTEXT,
                    snippet=edit,
                    visual="",
                )
                yield uid, snip

    snippets = {hashed: snip for hashed, snip in cont()}
    safe = LoadedSnips(exts=loaded.exts, snippets=snippets)

    coder = new_encoder(LoadedSnips)
    return recur_sort(coder(safe))
