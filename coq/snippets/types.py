from dataclasses import dataclass
from pathlib import PurePath
from typing import AbstractSet, Mapping
from uuid import UUID


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
    mtimes: Mapping[PurePath, float]
    exts: Mapping[str, AbstractSet[str]]
    snippets: Mapping[UUID, ParsedSnippet]
