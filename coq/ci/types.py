from dataclasses import dataclass
from pathlib import Path
from typing import AbstractSet, Mapping


@dataclass
class _CompilationPaths:
    lsp: AbstractSet[Path]
    neosnippet: AbstractSet[Path]
    ultisnip: AbstractSet[Path]


@dataclass(frozen=True)
class Compilation:
    git: AbstractSet[str]
    paths: _CompilationPaths
    remaps: Mapping[str, AbstractSet[str]]
