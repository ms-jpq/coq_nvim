from dataclasses import dataclass
from typing import AbstractSet, Mapping, Sequence


class LoadError(Exception):
    pass


@dataclass(frozen=True)
class ParsedSnippet:
    grammar: str
    content: str
    label: str
    doc: str
    matches: AbstractSet[str]
    options: AbstractSet[str]


_Type = str


@dataclass(frozen=True)
class MetaSnippets:
    snippets: Sequence[ParsedSnippet]
    extends: AbstractSet[_Type]


@dataclass(frozen=True)
class SnippetSpecs:
    snippets: Mapping[_Type, Sequence[ParsedSnippet]]
    extends: Mapping[_Type, AbstractSet[_Type]]


MetaSpecs = Mapping[str, SnippetSpecs]

