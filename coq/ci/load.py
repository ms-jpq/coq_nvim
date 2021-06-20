from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from subprocess import check_call
from urllib.parse import urlparse

from std2.pickle import decode
from std2.pickle.coders import BUILTIN_DECODERS
from yaml import safe_load

from ..consts import COMPILATION_YML,  TMP_DIR
from ..snippets.loaders.load import parse
from ..snippets.types import SnippetSpecs
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
    yaml = safe_load(COMPILATION_YML.read_bytes())
    specs: Compilation = decode(Compilation, yaml, decoders=BUILTIN_DECODERS)
    with ThreadPoolExecutor() as pool:
        tuple(pool.map(_git_pull, specs.git))

    parsed = parse(
        lsp={*map(_trans_name, specs.paths.lsp)},
        neosnippet={*map(_trans_name, specs.paths.neosnippet)},
        snipmate={*map(_trans_name, specs.paths.snipmate)},
        ultisnip={*map(_trans_name, specs.paths.ultisnip)},
    )
    return parsed

