from dataclasses import dataclass
from pathlib import Path
from typing import AbstractSet


@dataclass
class _CompilationPaths:
    lsp: AbstractSet[Path]
    neosnippet: AbstractSet[Path]
    snipmate: AbstractSet[Path]
    ultisnip: AbstractSet[Path]


@dataclass(frozen=True)
class Compilation:
    git: AbstractSet[str]
    paths: _CompilationPaths

