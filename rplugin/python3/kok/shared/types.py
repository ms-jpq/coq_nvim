from abc import abstractmethod
from dataclasses import dataclass, field
from typing import (
    Any,
    AsyncIterable,
    AsyncIterator,
    Awaitable,
    Callable,
    Mapping,
    Optional,
    Protocol,
    Sequence,
    Set,
    Sized,
    TypeVar,
    runtime_checkable,
)

from pynvim import Nvim

T = TypeVar("T")


@runtime_checkable
class Channel(Sized, AsyncIterable[T], Protocol[T]):
    @abstractmethod
    def __bool__(self) -> bool:
        ...

    @abstractmethod
    async def __anext__(self) -> T:
        ...

    @abstractmethod
    def full(self) -> bool:
        ...

    @abstractmethod
    def close(self) -> None:
        ...

    @abstractmethod
    async def send(self, item: T) -> None:
        ...

    @abstractmethod
    async def recv(self) -> T:
        ...


@dataclass(frozen=True)
class MatchOptions:
    transpose_band: int
    unifying_chars: Set[str]


@dataclass(frozen=True)
class Seed:
    match: MatchOptions
    config: Mapping[str, Any]


@dataclass(frozen=True)
class Position:
    row: int
    col: int


# |...                            line                            ...|
# |...        line_before          🐭          line_after         ...|
# |...   <syms_before><alum_before>🐭<alnums_after><syms_after>   ...|
@dataclass(frozen=True)
class Context:
    position: Position

    filename: str
    filetype: str

    line: str
    line_normalized: str
    line_before: str
    line_before_normalized: str
    line_after: str
    line_after_normalized: str

    alnums: str
    alnums_normalized: str
    alnums_before: str
    alnums_before_normalized: str
    alnums_after: str
    alnums_after_normalized: str

    syms: str
    syms_before: str
    syms_after: str

    alnum_syms: str
    alnum_syms_normalized: str
    alnum_syms_before: str
    alnum_syms_before_normalized: str
    alnum_syms_after: str
    alnum_syms_after_normalized: str


@dataclass(frozen=True)
class SEdit:
    new_text: str


@dataclass(frozen=True)
class MEdit:
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str


# end exclusve
@dataclass(frozen=True)
class LEdit:
    begin: Position
    end: Position
    new_text: str


@dataclass(frozen=True)
class Snippet:
    kind: str
    match: str
    content: str


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


Source = Callable[[Context], AsyncIterator[Completion]]
Factory = Callable[[Nvim, Seed], Awaitable[Source]]


@dataclass(frozen=True)
class SnippetSeed:
    match: MatchOptions
    config: Mapping[str, Any]


@dataclass(frozen=True)
class SnippetContext:
    context: Context
    snippet: Snippet


SnippetEngine = Callable[[SnippetContext], Awaitable[None]]
SnippetEngineFactory = Callable[[Nvim, SnippetSeed], Awaitable[SnippetEngine]]
