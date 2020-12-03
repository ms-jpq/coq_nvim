from dataclasses import dataclass, field
from math import inf
from typing import Any, Mapping, Optional, Sequence

from ..shared.types import (
    LEdit,
    MatchOptions,
    MEdit,
    Position,
    SEdit,
    Snippet,
    SnippetChans,
    SourceChans,
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
class SourceBundle:
    spec: SourceSpec
    chans: SourceChans


@dataclass(frozen=True)
class SnippetEngineBundle:
    spec: SnippetEngineSpec
    chans: SnippetChans


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
class Payload:
    position: Position
    sedit: Optional[SEdit]
    medit: Optional[MEdit]
    ledits: Sequence[LEdit]
    snippet: Optional[Snippet]
