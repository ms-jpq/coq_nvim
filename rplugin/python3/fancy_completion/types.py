from asyncio import Queue
from dataclasses import dataclass
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
class SourceSeed:
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


@dataclass(frozen=True)
class SourceFeed:
    filename: str
    filetype: str
    position: Position
    context: Context


@dataclass(frozen=True)
class SourceCompletion:
    position: Position
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str
    label: Optional[str] = None
    sortby: Optional[str] = None
    kind: Optional[str] = None
    doc: Optional[str] = None


Source = Callable[[SourceFeed], AsyncIterator[SourceCompletion]]
Factory = Callable[[Nvim, Queue, SourceSeed], Awaitable[Source]]


@dataclass(frozen=True)
class SourceFactory:
    name: str
    short_name: str
    timeout: float
    limit: float
    seed: SourceSeed
    manufacture: Factory


@dataclass(frozen=True)
class Step:
    source: str
    source_shortname: str
    text: str
    text_normalized: str
    comp: SourceCompletion


@dataclass(frozen=True)
class Payload:
    row: int
    col: int
    old_prefix: str
    new_prefix: str
    old_suffix: str
    new_suffix: str


@dataclass(frozen=True)
class State:
    char_inserted: bool
    sources: Set[str]
