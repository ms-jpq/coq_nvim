from concurrent.futures import ThreadPoolExecutor
from json import dumps
from pathlib import Path
from subprocess import check_call
from urllib.parse import urlparse

from std2.pickle import decode, encode
from std2.pickle.coders import BUILTIN_DECODERS
from std2.tree import recur_sort
from yaml import safe_load

from ..consts import COMPILATION_YML, SNIPPET_ARTIFACTS, TMP_DIR
from ..snippets.loaders.load import parse
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


def main() -> None:
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
    ordered = recur_sort(encode(parsed))
    json = dumps(ordered, check_circular=False, ensure_ascii=False, indent=2)
    SNIPPET_ARTIFACTS.write_text(json)

