from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Optional


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
class SourceFeed:
    position: Position


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    sortby: Optional[str] = None
    display: Optional[str] = None
    detail: Optional[str] = None


Source = Callable[[SourceFeed], AsyncIterator[SourceCompletion]]
