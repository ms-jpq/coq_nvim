from dataclasses import dataclass, field
from math import inf
from typing import Any, Dict, Optional, Sequence

from ..shared.types import (
    Completion,
    Factory,
    LEdit,
    MatchOptions,
    MEdit,
    Position,
    Seed,
    Snippet,
    SnippetEngineFactory,
    SnippetSeed,
)


@dataclass(frozen=True)
class Notification:
    source: str
    body: Sequence[Any]


@dataclass(frozen=True)
class DisplayOptions:
    ellipsis: str
    tabsize: int
    pum_max_len: int


@dataclass(frozen=True)
class CacheOptions:
    min_match: int
    band_size: int
    source_name: str = "cache"


@dataclass(frozen=True)
class SourceSpec:
    main: str
    enabled: bool
    short_name: str
    limit: Optional[float]
    rank: Optional[int]
    config: Dict[str, Any]


@dataclass(frozen=True)
class SnippetEngineSpec:
    main: str
    enabled: str
    kinds: Sequence[str]
    config: Dict[str, Any]


@dataclass(frozen=True)
class Settings:
    retries: int
    timeout: float
    logging_level: str
    display: DisplayOptions
    match: MatchOptions
    cache: CacheOptions
    sources: Dict[str, SourceSpec]
    snippet_engines: Dict[str, SnippetEngineSpec]


@dataclass(frozen=True)
class SourceFactory:
    enabled: bool
    short_name: str
    limit: float
    rank: float
    seed: Seed
    manufacture: Factory


@dataclass(frozen=True)
class EngineFactory:
    seed: SnippetSeed
    manufacture: SnippetEngineFactory


@dataclass(frozen=True)
class BufferSourceSpec:
    enabled: Optional[bool]


@dataclass(frozen=True)
class BufferContext:
    timeout: float = inf
    sources: Dict[str, BufferSourceSpec] = field(default_factory=dict)


@dataclass(frozen=True)
class Step:
    source: str
    source_shortname: str
    rank: float
    text: str
    text_normalized: str
    comp: Completion


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float
    matches: Dict[int, str]
    full_match: bool


@dataclass(frozen=True)
class Payload:
    position: Position
    medit: Optional[MEdit]
    ledits: Sequence[LEdit]
    snippet: Optional[Snippet]


@dataclass(frozen=True)
class State:
    char_inserted: bool
    comp_inserted: bool
