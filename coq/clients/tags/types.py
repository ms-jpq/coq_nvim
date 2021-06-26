from dataclasses import dataclass
from typing import Optional, Sequence


@dataclass(frozen=True)
class Header:
    filename: str
    byte_len: int


@dataclass(frozen=True)
class Tag:
    row: int
    col_offset: int
    name: Optional[str]
    text: str


@dataclass(frozen=True)
class Section:
    header: Header
    tags: Sequence[Tag]

