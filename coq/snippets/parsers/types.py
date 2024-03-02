from __future__ import annotations

from dataclasses import dataclass
from typing import Iterator, MutableSequence, Optional, Sequence, Tuple, Union

from std2.itertools import deiter

from ...shared.types import Context, TextTransform, TextTransforms


class ParseError(Exception): ...


@dataclass(frozen=True)
class Index:
    i: int
    row: int
    col: int


EChar = Tuple[Index, str]


@dataclass(frozen=True)
class ParseInfo:
    visual: str
    clipboard: str
    comment_str: Tuple[str, str]


@dataclass(frozen=True)
class ParserCtx(Iterator):
    ctx: Context
    text: str
    info: ParseInfo
    dit: deiter[EChar]
    stack: MutableSequence[Union[int, str]]

    def __iter__(self) -> ParserCtx:
        return self

    def __next__(self) -> EChar:
        return next(self.dit)


@dataclass(frozen=True)
class Unparsed:
    text: str


@dataclass(frozen=True)
class IntBegin:
    idx: int


@dataclass(frozen=True)
class VarBegin:
    name: str


@dataclass(frozen=True)
class Transform:
    var_subst: Optional[str]
    maybe_idx: int
    xform: TextTransform


@dataclass(frozen=True)
class End: ...


Token = Union[Unparsed, IntBegin, Transform, VarBegin, End, str]
TokenStream = Iterator[Token]


@dataclass(frozen=True)
class Region:
    begin: int
    end: int
    text: str


@dataclass(frozen=True)
class Parsed:
    text: str
    cursor: int
    regions: Sequence[Tuple[int, Region]]
    xforms: TextTransforms
