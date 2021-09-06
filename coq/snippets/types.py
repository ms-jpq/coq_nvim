from dataclasses import dataclass
from typing import AbstractSet, Mapping
from uuid import UUID

SCHEMA = "v2"


class LoadError(Exception):
    ...


@dataclass(frozen=True)
class ParsedSnippet:
    grammar: str
    filetype: str
    content: str
    label: str
    doc: str
    matches: AbstractSet[str]


@dataclass(frozen=True)
class LoadedSnips:
    exts: Mapping[str, AbstractSet[str]]
    snippets: Mapping[UUID, ParsedSnippet]
