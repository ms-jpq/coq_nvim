from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Generic, Iterator, Sequence, Tuple, TypeVar, Union

from ...shared.types import Context, NvimPos

T = TypeVar("T")

from std2.itertools import deiter


class ParseError(Exception):
    pass


@dataclass(frozen=True)
class Index:
    i: int
    row: int
    col: int


EChar = Tuple[Index, str]


@dataclass(frozen=True)
class ParserCtx(Generic[T], Iterator):
    ctx: Context
    dit: deiter[EChar]
    text: str
    local: T

    def __iter__(self) -> ParserCtx:
        return self

    def __next__(self) -> EChar:
        return next(self.dit)


@dataclass(frozen=True)
class Unparsed:
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


Token = Union[Unparsed, Begin, DummyBegin, End, str]
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

