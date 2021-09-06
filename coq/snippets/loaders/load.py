from dataclasses import asdict
from os.path import normcase
from pathlib import Path
from typing import AbstractSet, Iterable, Iterator, MutableMapping, MutableSet
from uuid import UUID, uuid3

from std2.graphlib import recur_sort
from std2.pathlib import walk

from ..types import LoadedSnips, ParsedSnippet
from .lsp import load_lsp
from .neosnippet import load_neosnippet
from .ultisnip import load_ultisnip


def _load_paths(search: Iterable[Path], exts: AbstractSet[str]) -> Iterator[Path]:
    for search_path in search:
        for path in walk(search_path):
            if path.suffix in exts:
                yield Path(normcase(path))


def _key(snip: ParsedSnippet) -> UUID:
    name = (
        snip.grammar
        + snip.filetype
        + snip.content
        + snip.label
        + snip.doc
        + "".join(sorted(snip.matches))
    )
    return uuid3(UUID(int=0), name=name)


def load_direct(
    lsp: Iterable[Path],
    neosnippet: Iterable[Path],
    ultisnip: Iterable[Path],
) -> LoadedSnips:
    specs = {load_lsp: lsp, load_neosnippet: neosnippet, load_ultisnip: ultisnip}

    extensions: MutableMapping[str, MutableSet[str]] = {}
    snippets: MutableMapping[UUID, ParsedSnippet] = {}

    for parser, paths in specs.items():
        for path in paths:
            with path.open(encoding="UTF-8") as fd:
                filetype, exts, snips = parser(path, enumerate(fd, start=1))
            ext_acc = extensions.setdefault(filetype, set())
            for ext in exts:
                ext_acc.add(ext)
            for snip in snips:
                uid = _key(snip)
                snippets[uid] = snip

    loaded = LoadedSnips(exts=extensions, snippets=snippets)
    return loaded


def load_ci(
    lsp: Iterable[Path],
    neosnippet: Iterable[Path],
    ultisnip: Iterable[Path],
) -> LoadedSnips:
    loaded = load_direct(
        lsp=_load_paths(lsp, exts={".json"}),
        neosnippet=_load_paths(neosnippet, exts={".snippets", ".snip"}),
        ultisnip=_load_paths(ultisnip, exts={".snippets", ".snip"}),
    )

    return loaded
