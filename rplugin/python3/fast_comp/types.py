from __future__ import annotations

from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Optional

from pynvim import Nvim


@dataclass(frozen=True)
class Settings:
    pass


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


@dataclass(frozen=True)
class SourceFactory:
    name: str
    priority: int
    timeout: Optional[float]
    manufacture = Callable[[Nvim, Any], Source]


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
