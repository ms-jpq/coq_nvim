from dataclasses import dataclass
from enum import Enum, auto
from typing import AbstractSet, Mapping, Optional, Sequence


class LoadError(Exception):
    pass


class Options(Enum):
    b = auto()
    i = auto()
    w = auto()
    r = auto()
    t = auto()
    s = auto()
    m = auto()
    e = auto()
    a = auto()
    word = auto()
    head = auto()
    indent = auto()


@dataclass(frozen=True)
class ParsedSnippet:
    grammar: str
    content: str
    label: Optional[str]
    doc: Optional[str]
    matches: AbstractSet[str]
    opts: AbstractSet[Options]


@dataclass(frozen=True)
class MetaSnippets:
    snippets: Sequence[ParsedSnippet]
    extends: AbstractSet[str]


@dataclass(frozen=True)
class SnippetSpecs:
    snippets: Mapping[str, Sequence[ParsedSnippet]]
    extends: Mapping[str, AbstractSet[str]]

