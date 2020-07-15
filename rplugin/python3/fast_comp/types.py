from __future__ import annotations

from dataclasses import dataclass
from typing import Any, AsyncIterator, Callable, Optional

from pynvim import Nvim


@dataclass
class Settings:
    pass


@dataclass
class SourceSeed:
    priority: Optional[int]
    bespoke: Any = None


@dataclass
class SourceFeed:
    cwd: str
    cword: str


@dataclass
class SemiCompletion:
    display: str
    content: str


@dataclass
class Completion:
    source: str
    priority: int
    display: str
    content: str


@dataclass
class Source:
    name: str
    priority: int
    step: Callable[[Source, SourceFeed], AsyncIterator[SemiCompletion]]
    timeout: Optional[float]


SourceFactory = Callable[[Nvim, SourceSeed], Source]
