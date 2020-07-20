from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Dict, Optional


@dataclass(frozen=True)
class SourceSeed:
    limit: float
    timeout: float
    config: Dict[str, Any]


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
