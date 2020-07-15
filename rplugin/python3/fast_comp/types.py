from __future__ import annotations

from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Optional

from pynvim import Nvim


@dataclass(frozen=True)
class Settings:
    pass


@dataclass(frozen=True)
class SourceSeed:
    priority: Optional[int]
    bespoke: Any = None


@dataclass(frozen=True)
class SourceFeed:
    cwd: str
    cword: str


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    display: Optional[str]


@dataclass(frozen=True)
class VimCompletion:
    word: str
    abbr: Optional[str] = None
    menu: Optional[str] = None
    info: Optional[str] = None
    kind: Optional[str] = None
    icase: Optional[int] = None
    equal: Optional[int] = None
    dup: Optional[int] = None
    empty: Optional[int] = None
    user_data: Optional[Any] = None


@dataclass(frozen=True)
class Source:
    name: str
    priority: int
    step: Callable[[Source, SourceFeed], AsyncIterator[SourceCompletion]]
    timeout: Optional[float]


SourceFactory = Callable[[Nvim, SourceSeed], Source]
