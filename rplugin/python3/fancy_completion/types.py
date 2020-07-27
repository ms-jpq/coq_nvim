from asyncio import Queue
from dataclasses import dataclass, field
from typing import (
    Any,
    AsyncIterator,
    Awaitable,
    Callable,
    Dict,
    Optional,
    Sequence,
    Set,
)

from pynvim import Nvim


@dataclass(frozen=True)
class Notification:
    source: str
    body: Sequence[Any]


@dataclass(frozen=True)
class FuzzyOptions:
    min_match: int


@dataclass(frozen=True)
class SourceSpec:
    main: str
    short_name: str
    enabled: bool
    limit: Optional[float]
    timeout: Optional[float]
    config: Dict[str, Any]


@dataclass(frozen=True)
class Settings:
    fuzzy: FuzzyOptions
    sources: Dict[str, SourceSpec]


@dataclass(frozen=True)
class Seed:
    limit: float
    timeout: float
    config: Optional[Any] = None


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
    alnums_after: str

    syms: str
    syms_before: str
    syms_after: str


# end exclusve
@dataclass(frozen=True)
class LEdit:
    begin: Position
    end: Position
    new_text: str


@dataclass(frozen=True)
class Completion:
    position: Position
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str
    label: Optional[str] = None
    sortby: Optional[str] = None
    kind: Optional[str] = None
    doc: Optional[str] = None
    ledits: Sequence[LEdit] = field(default_factory=tuple)


Source = Callable[[Context], AsyncIterator[Completion]]
Factory = Callable[[Nvim, Queue, Seed], Awaitable[Source]]


@dataclass(frozen=True)
class SourceFactory:
    name: str
    short_name: str
    timeout: float
    limit: float
    seed: Seed
    manufacture: Factory


@dataclass(frozen=True)
class Step:
    source: str
    source_shortname: str
    text: str
    text_normalized: str
    comp: Completion


@dataclass(frozen=True)
class Payload:
    position: Position
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str
    ledits: Sequence[LEdit]


@dataclass(frozen=True)
class State:
    char_inserted: bool
    comp_inserted: bool
    sources: Set[str]
