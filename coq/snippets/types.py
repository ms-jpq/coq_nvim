from dataclasses import dataclass
from typing import AbstractSet, Mapping, Sequence, Tuple, TypedDict, TypeVar


class LoadError(Exception):
    ...


@dataclass(frozen=True)
class ParsedSnippet:
    grammar: str
    content: str
    label: str
    doc: str
    matches: AbstractSet[str]
    options: AbstractSet[str]


T = TypeVar("T")

_Label = str
_Type = str

ASnips = Mapping[
    _Label,
    Tuple[Mapping[_Type, Sequence[_Type]], Mapping[_Type, Sequence[ParsedSnippet]]],
]

