from __future__ import annotations

from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Dict, Optional

from pynvim import Nvim


@dataclass(frozen=True)
class SourceSeed:
    priority: int = 0
    bespoke: Optional[Any] = None


@dataclass(frozen=True)
class Settings:
    sources: Dict[str, SourceSeed]


@dataclass(frozen=True)
class SourceFeed:
    cwd: str
    cword: str


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    display: Optional[str]
    preview: Optional[str]


Source = Callable[[SourceFeed], AsyncIterator[SourceCompletion]]
Factory = Callable[[Nvim, Any], Source]


@dataclass(frozen=True)
class SourceFactory:
    name: str
    timeout: Optional[float]
    manufacture: Factory


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
