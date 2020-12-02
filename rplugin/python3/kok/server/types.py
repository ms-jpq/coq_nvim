from dataclasses import dataclass, field
from math import inf
from typing import Any, Mapping, Optional, Sequence

from ..shared.types import (
    Factory,
    LEdit,
    MatchOptions,
    MEdit,
    Position,
    SEdit,
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
class SourceSpec:
    main: str
    enabled: bool
    short_name: str
    limit: float
    rank: int
    unique: bool
    config: Mapping[str, Any]


@dataclass(frozen=True)
class SnippetEngineSpec:
    main: str
    enabled: str
    kinds: Sequence[str]
    config: Mapping[str, Any]


@dataclass(frozen=True)
class Settings:
    retries: int
    timeout: float
    logging_level: str
    display: DisplayOptions
    match: MatchOptions
    sources: Mapping[str, SourceSpec]
    snippet_engines: Mapping[str, SnippetEngineSpec]


@dataclass(frozen=True)
class SourceFactory:
    enabled: bool
    short_name: str
    limit: float
    rank: int
    unique: bool
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
    sources: Mapping[str, BufferSourceSpec] = field(default_factory=dict)


@dataclass(frozen=True)
class Suggestion:
    position: Position
    source: str
    source_shortname: str
    unique: bool
    rank: float
    match: str
    match_normalized: str
    kind: Optional[str]
    label: Optional[str]
    doc: Optional[str]
    sortby: Optional[str]
    sedit: Optional[SEdit]
    medit: Optional[MEdit]
    ledits: Sequence[LEdit]
    snippet: Optional[Snippet]


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float
    matches: Mapping[int, str]
    full_match: bool


@dataclass(frozen=True)
class Step:
    suggestion: Suggestion
    metric: Metric


@dataclass(frozen=True)
class Payload:
    position: Position
    sedit: Optional[SEdit]
    medit: Optional[MEdit]
    ledits: Sequence[LEdit]
    snippet: Optional[Snippet]


@dataclass(frozen=True)
class State:
    char_inserted: bool
    comp_inserted: bool
