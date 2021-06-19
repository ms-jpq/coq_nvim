from dataclasses import dataclass
from typing import AbstractSet


@dataclass
class _CompilationPaths:
    lsp: AbstractSet[str]
    neosnippet: AbstractSet[str]
    snipmate: AbstractSet[str]
    ultisnips: AbstractSet[str]


@dataclass(frozen=True)
class Compilation:
    git: AbstractSet[str]
    paths: _CompilationPaths

