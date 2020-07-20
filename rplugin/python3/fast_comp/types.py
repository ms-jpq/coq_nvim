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
    Union,
)

from pynvim import Nvim


@dataclass(frozen=True)
class Notification:
    source: str
    body: Sequence[Any]


@dataclass(frozen=True)
class FuzzyOptions:
    cache_size: int
    band_size: int
    min_match: int


@dataclass(frozen=True)
class SourceSpec:
    main: str
    short_name: str
    enabled: bool
    priority: Optional[float]
    limit: Optional[float]
    timeout: Optional[float]
    config: Optional[Any]


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


@dataclass(frozen=True)
class Prefix:
    line: str
    alnums: str
    syms: str


@dataclass(frozen=True)
class SourceFeed:
    filename: str
    filetype: str
    position: Position
    prefix: Prefix


@dataclass(frozen=True)
class SourceCompletion:
    text: str
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
    priority: float
    timeout: float
    limit: float
    seed: SourceSeed
    manufacture: Factory


@dataclass(frozen=True)
class Step:
    source: str
    source_shortname: str
    priority: float
    normalized: str
    comp: SourceCompletion


@dataclass(frozen=True)
class State:
    char_inserted: bool
