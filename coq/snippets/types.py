from dataclasses import dataclass
from typing import AbstractSet, Literal, Mapping, Sequence, Tuple


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


_Label = str
_Type = str

ASnips = Mapping[
    _Label,
    Tuple[
        Mapping[_Type, Mapping[_Type, Literal[True]]],
        Mapping[_Type, Sequence[ParsedSnippet]],
    ],
]

