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
    filetype: str
    position: Position
    line: str
    prefix: str


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    label: str
    sortby: Optional[str] = None
    kind: Optional[str] = None
    doc: Optional[str] = None


Source = Callable[[SourceFeed], AsyncIterator[SourceCompletion]]
