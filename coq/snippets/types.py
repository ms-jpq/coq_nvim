from dataclasses import dataclass
from pathlib import Path
from typing import AbstractSet, Mapping
from uuid import UUID

SCHEMA = "v2"


class LoadError(Exception):
    ...


@dataclass(frozen=True)
class ParsedSnippet:
    filetype: str
    grammar: str
    content: str
    label: str
    doc: str
    matches: AbstractSet[str]


@dataclass(frozen=True)
class LoadedSnips:
    mtimes: Mapping[Path, float]
    exts: Mapping[str, AbstractSet[str]]
    snippets: Mapping[UUID, ParsedSnippet]
