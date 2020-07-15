from __future__ import annotations

from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Dict, Optional

from pynvim import Nvim


@dataclass
class SourceSpec:
    main: str
    enabled: bool
    priority: float
    short_name: str
    timeout: float
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
