from dataclasses import dataclass
from enum import Enum, auto
from typing import Optional, Sequence, Set, Tuple


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
class MetaSnippet:
    content: str
    label: Optional[str]
    doc: Optional[str]
    matches: Set[str]
    opts: Set[Options]


LoadSingle = Tuple[Sequence[MetaSnippet], Sequence[str]]
