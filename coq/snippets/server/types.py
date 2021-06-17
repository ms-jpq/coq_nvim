from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Callable, Generic, Iterator, Sequence, Tuple, TypeVar, Union

from ..shared.types import Context, Position

T = TypeVar("T")


class ParseError(Exception):
    pass


@dataclass(frozen=True)
class Index:
    i: int
    row: int
    col: int


EChar = Tuple[Index, str]


@dataclass(frozen=True)
class ParseContext(Generic[T], Iterator):
    vals: Context
    queue: deque
    text: str
    local: T

    def __iter__(self) -> ParseContext:
        return self

    def __next__(self) -> EChar:
        if self.queue:
            char = self.queue.popleft()
            return char
        else:
            raise StopIteration


@dataclass(frozen=True)
class Unparsable:
    text: str


@dataclass(frozen=True)
class Begin:
    idx: int


@dataclass(frozen=True)
class DummyBegin:
    pass


@dataclass(frozen=True)
class End:
    pass


Token = Union[Unparsable, Begin, DummyBegin, End, str]
TokenStream = Iterator[Token]


@dataclass(frozen=True)
class Region:
    idx: int
    begin: int
    end: int


@dataclass(frozen=True)
class Parsed:
    text: str
    cursor: int
    regions: Sequence[Region]


Parser = Callable[[Context, str], Parsed]


@dataclass(frozen=True)
class InstanceSettings:
    prefer_tabs: bool
    tab_width: int


@dataclass(frozen=True)
class Mark:
    name: str
    begin: Position
    end: Position


@dataclass(frozen=True)
class Expanded:
    text: str
    pos: Position
    marks: Sequence[Mark]
