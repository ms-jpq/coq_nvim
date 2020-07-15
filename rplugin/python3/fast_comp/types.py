from __future__ import annotations

from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Dict, Optional

from pynvim import Nvim


@dataclass
class SourceSpec:
    main: str
    enabled: bool
    priority: float
    short: str
    config: Any


@dataclass(frozen=True)
class Settings:
    sources: Dict[str, SourceSpec]


@dataclass(frozen=True)
class SourceSeed:
    config: Optional[Any] = None


@dataclass(frozen=True)
class SourceCompletion:
    text: str
    display: Optional[str] = None
    preview: Optional[str] = None


Source = AsyncIterator[SourceCompletion]
Factory = Callable[[Nvim, SourceSeed], AsyncIterator[Source]]


@dataclass(frozen=True)
class SourceFactory:
    name: str
    short_name: str
    priority: float
    timeout: float
    seed: SourceSeed
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
