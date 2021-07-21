from locale import strxfrm
from pathlib import Path
from typing import AbstractSet, Mapping, MutableMapping, MutableSequence, MutableSet

from std2.pathlib import walk

from ..types import ParsedSnippet, SnippetSpecs
from .lsp import parse as parse_lsp
from .neosnippet import parse as parse_neosnippets
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


def load(
    lsp: AbstractSet[Path], neosnippet: AbstractSet[Path], ultisnip: AbstractSet[Path]
) -> SnippetSpecs:
    specs = {
        parse_lsp: _load_paths(lsp, exts={".json"}),
        parse_neosnippets: _load_paths(neosnippet, exts={".snippets", ".snip"}),
        parse_ultisnip: _load_paths(ultisnip, exts={".snippets", ".snip"}),
    }

    acc: MutableMapping[str, MutableSequence[ParsedSnippet]] = {}
    exts: MutableMapping[str, MutableSet[str]] = {}

    for parser, spec in specs.items():
        for ext, paths in spec.items():
            snippets = acc.setdefault(ext, [])
            extends = exts.setdefault(ext, set())
            for path in sorted(paths, key=lambda p: tuple(map(strxfrm, p.parts))):
                meta = parser(path)
                snippets.extend(meta.snippets)
                for e in meta.extends:
                    extends.add(e)

    final = SnippetSpecs(snippets=acc, extends=exts)
    return final

