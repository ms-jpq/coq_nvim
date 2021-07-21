from locale import strxfrm
from pathlib import Path
from typing import (
    AbstractSet,
    Iterator,
    Mapping,
    MutableMapping,
    MutableSequence,
    MutableSet,
    Sequence,
    Tuple,
)

from std2.pathlib import walk

from ..types import ASnips, ParsedSnippet
from .lsp import parse as parse_lsp
from .neosnippet import parse as parse_neosnippets
from .ultisnip import parse as parse_ultisnip


def _load_paths(
    search: Mapping[str, Path], exts: AbstractSet[str]
) -> Mapping[str, Tuple[str, Path]]:
    def cont() -> Iterator[Tuple[str, str, Path]]:
        for label, search_path in search.items():
            for path in walk(search_path):
                if path.suffix in exts:
                    yield label, path.stem, path

    return {label: (ext, path) for label, ext, path in cont()}


def load(
    lsp: Mapping[str, Path],
    neosnippet: Mapping[str, Path],
    ultisnip: Mapping[str, Path],
) -> ASnips:
    specs = {
        parse_lsp: _load_paths(lsp, exts={".json"}),
        parse_neosnippets: _load_paths(neosnippet, exts={".snippets", ".snip"}),
        parse_ultisnip: _load_paths(ultisnip, exts={".snippets", ".snip"}),
    }

    def c1() -> Iterator[Tuple[str, str, AbstractSet[str], Sequence[ParsedSnippet]]]:
        for parser, spec in specs.items():
            for label, (ext, path) in spec.items():
                parsed = parser(path)
                yield label, ext, *parsed

    meta: MutableMapping[
        str,
        Tuple[
            MutableMapping[str, MutableSet[str]],
            MutableMapping[str, MutableSequence[ParsedSnippet]],
        ],
    ] = {}
    for label, ext, extends, snippets in c1():
        exts, snips = meta.setdefault(label, ({}, {}))
        e_acc = exts.setdefault(ext, set())
        s_acc = snips.setdefault(ext, [])
        for e in extends:
            e_acc.add(e)
        for s in snippets:
            s_acc.append(s)

    fin = {
        label: ({k: sorted(v, key=strxfrm) for k, v in exts.items()}, snips)
        for label, (exts, snips) in meta.items()
    }
    return fin

