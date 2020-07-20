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
class Context:
    line: str
    line_before: str
    line_after: str
    alnums_before: str
    alnums_after: str
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
    old_suffix: str = ""
    new_suffix: str = ""
    label: Optional[str] = None
    sortby: Optional[str] = None
    kind: Optional[str] = None
    doc: Optional[str] = None


Source = Callable[[SourceFeed], AsyncIterator[SourceCompletion]]
