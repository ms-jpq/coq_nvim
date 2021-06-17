from pathlib import Path
from typing import AbstractSet, Iterator, Mapping, MutableMapping, MutableSet

from std2.pathlib import walk

from .lsp import parse as parse_lsp
from .neosnippet import parse as parse_neosnippets
from .snipmate import parse as parse_snipmate
from .types import MetaSnippets
from .ultisnip import parse as parse_ultisnip


def _load_paths(
    search: AbstractSet[Path], exts: AbstractSet[str]
) -> Mapping[str, AbstractSet[Path]]:
    acc: MutableMapping[str, MutableSet[Path]] = {}

    for search_path in search:
        for path in walk(search_path):
            if path.suffix in exts:
                tmp = acc.setdefault(path.stem, set())
                tmp.add(path)

    return acc


def parse() -> Mapping[str, MetaSnippets]:
    return {}

