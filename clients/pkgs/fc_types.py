from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Callable, Dict, Optional, Sequence


@dataclass(frozen=True)
class Seed:
    limit: float
    timeout: float
    config: Dict[str, Any]


@dataclass(frozen=True)
class Position:
    row: int
    col: int


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


@dataclass(frozen=True)
class Edit:
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
    edits: Sequence[Edit] = field(default_factory=tuple)


Source = Callable[[Context], AsyncIterator[Completion]]
