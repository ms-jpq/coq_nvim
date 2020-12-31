from __future__ import annotations

from abc import abstractmethod
from dataclasses import dataclass, field
from typing import (
    Any,
    AsyncIterable,
    Awaitable,
    Callable,
    Mapping,
    Optional,
    Protocol,
    Sequence,
    Set,
    Sized,
    Tuple,
    TypeVar,
    runtime_checkable,
)

from pynvim import Nvim

T = TypeVar("T")


@dataclass(frozen=True)
class MatchOptions:
    transpose_band: int
    unifying_chars: Set[str]


@dataclass(frozen=True)
class Seed:
    match: MatchOptions
    config: Mapping[str, Any]





@dataclass(frozen=True)
class Completion:
    position: Position
    label: Optional[str] = None
    sortby: Optional[str] = None
    kind: Optional[str] = None
    doc: Optional[str] = None
    sedit: Optional[SEdit] = None
    medit: Optional[MEdit] = None
    ledits: Sequence[LEdit] = field(default_factory=tuple)
    snippet: Optional[Snippet] = None


@dataclass(frozen=True)
class SourceChans:
    comm_ch: Channel[Any]
    send_ch: Channel[Tuple[int, Context]]
    recv_ch: Channel[Tuple[int, Channel[Completion]]]


Source = Callable[[Nvim, Seed], Awaitable[SourceChans]]


@dataclass(frozen=True)
class SnippetContext:
    context: Context
    snippet: Snippet


@dataclass(frozen=True)
class SnippetChans:
    send_ch: Channel[Tuple[int, SnippetContext]]
    recv_ch: Channel[Tuple[int, MEdit]]


SnippetHandler = Callable[[Nvim, Seed], Awaitable[SnippetChans]]
