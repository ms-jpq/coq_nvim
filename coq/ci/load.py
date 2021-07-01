from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from subprocess import check_call
from typing import MutableMapping, MutableSequence
from urllib.parse import urlparse

from std2.pickle import new_decoder, new_encoder
from yaml import safe_load

from ..consts import COMPILATION_YML, TMP_DIR
from ..shared.context import EMPTY_CONTEXT
from ..shared.types import SnippetEdit
from ..snippets.loaders.load import load as load_from_paths
from ..snippets.parse import parse
from ..snippets.parsers.parser import ParseError
from ..snippets.types import ParsedSnippet, SnippetSpecs
from .types import Compilation


def _p_name(uri: str) -> Path:
    return TMP_DIR / Path(urlparse(uri).path).name


def _git_pull(uri: str) -> None:
    location = _p_name(uri)
    if location.is_dir():
        check_call(("git", "pull", "--recurse-submodules"), cwd=location)
    else:
        check_call(
            (
                "git",
                "clone",
                "--depth=1",
                "--recurse-submodules",
                "--shallow-submodules",
                uri,
                str(location),
            ),
            cwd=TMP_DIR,
        )


def _trans_name(relative: Path) -> Path:
    return TMP_DIR / relative


def load() -> SnippetSpecs:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    yaml = safe_load(COMPILATION_YML.read_bytes())
    specs: Compilation = new_decoder(Compilation)(yaml)
    with ThreadPoolExecutor() as pool:
        tuple(pool.map(_git_pull, specs.git))

    parsed = load_from_paths(
        lsp={*map(_trans_name, specs.paths.lsp)},
        neosnippet={*map(_trans_name, specs.paths.neosnippet)},
        ultisnip={*map(_trans_name, specs.paths.ultisnip)},
    )
    return parsed


def load_parsable() -> SnippetSpecs:
    specs = load()
    acc: MutableMapping[str, MutableSequence[ParsedSnippet]] = {}

    for ext, snippets in specs.snippets.items():
        snips = acc.setdefault(ext, [])
        for snippet in snippets:
            edit = SnippetEdit(
                new_text=snippet.content,
                grammar=snippet.grammar,
            )
            try:
                parse(
                    set(),
                    context=EMPTY_CONTEXT,
                    snippet=edit,
                    visual="",
                )
            except ParseError:
                pass
            else:
                snips.append(snippet)

    good_specs = SnippetSpecs(
        extends=specs.extends,
        snippets=acc,
    )
    return good_specs

